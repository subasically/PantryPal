import SwiftUI
@preconcurrency import AVFoundation
import CoreImage.CIFilterBuiltins

struct HouseholdSharingView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var confettiCenter: ConfettiCenter
    @StateObject private var viewModel = HouseholdSharingViewModel()
    @State private var showJoinSheet = false
    
    // Computed property to check Premium from AuthViewModel directly
    private var isPremium: Bool {
        authViewModel.currentHousehold?.isPremium == true
    }
    
    var body: some View {
        List {
            // Invite Section
            Section {
                if viewModel.isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Generating invite code...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if let invite = viewModel.currentInvite {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            // QR Code (encodes just the code for scanner compatibility)
                            if let qrImage = generateQRCode(from: invite.code) {
                                Image(uiImage: qrImage)
                                    .interpolation(.none)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 200, height: 200)
                                    .background(Color.white)
                                    .cornerRadius(12)
                            }
                            
                            // Code Display
                            HStack(spacing: 4) {
                                ForEach(Array(invite.code), id: \.self) { char in
                                    Text(String(char))
                                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                                        .frame(width: 32, height: 40)
                                        .background(Color.ppPurple.opacity(0.2))
                                        .foregroundColor(Color.ppPrimary)
                                        .cornerRadius(6)
                                }
                            }
                        }
                        
                        Text("Expires in 24 hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Share Button (shares code only)
                        ShareLink(
                            item: "Join my PantryPal with code: \(invite.code)",
                            subject: Text("Join my PantryPal"),
                            message: Text("Use this code to join: \(invite.code)")
                        ) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(.white)
                                Text("Share Invite")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ppPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                } else {
                    if !isPremium {
                        Button {
                            showPaywall = true
                        } label: {
                            HStack {
                                Image(systemName: "lock.fill")
                                Text("Invite Family Members (Premium)")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ppPrimary)
                        .controlSize(.regular) // Standard height
                        
                        Text("Household sharing requires Premium.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Button {
                            Task {
                                await viewModel.generateInvite()
                            }
                        } label: {
                            HStack {
                                if viewModel.isLoading {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                } else {
                                    Image(systemName: "qrcode")
                                }
                                Text(viewModel.isLoading ? "Generating..." : "Generate Invite Code")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ppPrimary)
                        .disabled(viewModel.isLoading)
                        .controlSize(.regular)
                    }
                }
            } header: {
                Text("Household Sharing")
            } footer: {
                if viewModel.isPremium {
                    Text("Share this code or QR with family members so they can join your household and share the pantry inventory.")
                }
            }
            
            // Join Section
            Section {
                Button {
                    showJoinSheet = true
                } label: {
                    HStack {
                        Image(systemName: "person.badge.plus")
                        Text("Join Another Household")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                }
            } footer: {
                Text("Enter an invite code to join someone else's household. You'll share their pantry inventory.")
            }
            
            // Members Section
            Section {
                if viewModel.isLoadingMembers {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(Array(viewModel.members.enumerated()), id: \.element.id) { index, member in
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.title2)
                                .foregroundColor(Color.ppPrimary)
                            
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(member.displayName)
                                        .font(.headline)
                                    
                                    if member.isOwner {
                                        Text("Owner")
                                            .font(.caption2)
                                            .fontWeight(.medium)
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(.systemGray5))
                                            .cornerRadius(4)
                                    }
                                }
                                Text(member.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Household Members")
            }
        }
        .navigationTitle("Household Sharing")
        .sheet(isPresented: $showJoinSheet) {
            JoinHouseholdView(onJoinSuccess: {
                Task {
                    try? await SyncService.shared.syncFromRemote(modelContext: modelContext)
                    await viewModel.loadMembers()
                    await viewModel.checkPremiumStatus()
                }
            })
        }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .task {
            await viewModel.checkPremiumStatus()
            await viewModel.loadMembers()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showPaywall)) { _ in
            // We need to present the paywall. Since this view is likely in a NavigationStack,
            // we might need a sheet.
            // For now, let's assume the parent view handles it or we add a sheet here.
            // Actually, let's add a sheet here to be safe.
            showPaywall = true
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(limit: authViewModel.freeLimit, reason: .householdSharing)
        }
        .overlay {
            if confettiCenter.isActive {
                ConfettiOverlay()
            }
        }
    }
    
    @State private var showPaywall = false
    
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

struct JoinHouseholdView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel
    @StateObject private var viewModel = JoinHouseholdViewModel()
    @State private var showScanner = false
    @State private var showSwitchConfirmation = false
    var onJoinSuccess: (() -> Void)?
    
    private var hasExistingHousehold: Bool {
        authViewModel.currentHousehold != nil
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Code Entry
                VStack(spacing: 12) {
                    Text("Enter Invite Code")
                        .font(.headline)
                    
                    // Simplified code display
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            CodeCharacterView(code: viewModel.code, index: index)
                        }
                    }
                    
                    AppTextField(
                        placeholder: "Enter or paste code",
                        text: $viewModel.code,
                        autocapitalization: .characters,
                        autocorrectionDisabled: true
                    )
                    .onChange(of: viewModel.code) { _, newValue in
                        viewModel.code = String(newValue.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                        if viewModel.code.count == 6 {
                            Task {
                                await viewModel.validateCode()
                            }
                        }
                    }
                }
                
                // Scan QR Button
                Button {
                    showScanner = true
                } label: {
                    HStack {
                        Image(systemName: "qrcode.viewfinder")
                        Text("Scan QR Code")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                
                Divider()
                
                // Validation Result
                if viewModel.isValidating {
                    ProgressView("Validating code...")
                } else if let validation = viewModel.validationResult {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Color.ppTertiary)
                        
                        Text(validation.householdName)
                            .font(.title2.bold())
                        
                        Text("\(validation.memberCount) member\(validation.memberCount == 1 ? "" : "s")")
                            .foregroundColor(.secondary)
                        
                        Button {
                            if hasExistingHousehold {
                                // Show confirmation dialog first
                                showSwitchConfirmation = true
                            } else {
                                // No household, join directly
                                Task {
                                    await viewModel.joinHousehold()
                                    if viewModel.showSuccess {
                                        onJoinSuccess?()
                                        await authViewModel.refreshCurrentUser()
                                    }
                                }
                            }
                        } label: {
                            Text(hasExistingHousehold ? "Switch Household" : "Join Household")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ppPrimary)
                        .disabled(viewModel.isJoining)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Join Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showScanner) {
                QRScannerView { code in
                    viewModel.code = code.uppercased()
                    showScanner = false
                    Task {
                        await viewModel.validateCode()
                    }
                }
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Switch Household?", isPresented: $showSwitchConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Switch", role: .destructive) {
                    Task {
                        await viewModel.joinHousehold()
                        if viewModel.showSuccess {
                            onJoinSuccess?()
                            await authViewModel.refreshCurrentUser()
                            dismiss()
                        }
                    }
                }
            } message: {
                if let currentHousehold = authViewModel.currentHousehold {
                    Text("You'll leave '\(currentHousehold.name)' and join '\(viewModel.validationResult?.householdName ?? "this household")'. Your local inventory will be replaced with the new household's items.")
                } else {
                    Text("You'll join '\(viewModel.validationResult?.householdName ?? "this household")'.")
                }
            }
            .alert("Success", isPresented: $viewModel.showSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("You've joined the household! Refresh your inventory to see shared items.")
            }
        }
    }
}

// Helper view for code character display
struct CodeCharacterView: View {
    let code: String
    let index: Int
    
    var character: String {
        let codeArray = Array(code)
        if index < codeArray.count {
            return String(codeArray[index])
        }
        return ""
    }
    
    var body: some View {
        Text(character)
            .font(.system(size: 24, weight: .bold, design: .monospaced))
            .frame(width: 44, height: 56)
            .background(Color(.systemGray6))
            .cornerRadius(8)
    }
}

// MARK: - View Models

@MainActor
class HouseholdSharingViewModel: ObservableObject {
    @Published var currentInvite: InviteCodeResponse?
    @Published var members: [HouseholdMember] = []
    @Published var isPremium = false
    @Published var isLoading = false
    @Published var isLoadingMembers = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    func checkPremiumStatus() async {
        if let household = try? await APIService.shared.getCurrentUser().1 {
            isPremium = household.isPremium ?? false
        }
    }
    
    func generateInvite() async {
        // Check premium status first
        await checkPremiumStatus()
        if !isPremium {
            NotificationCenter.default.post(name: .showPaywall, object: nil)
            return
        }
        
        isLoading = true
        do {
            currentInvite = try await APIService.shared.generateInviteCode()
        } catch {
            // If server returns 403, it will be caught here too, but we try to catch it early
            if error.userFriendlyMessage.contains("Premium") {
                NotificationCenter.default.post(name: .showPaywall, object: nil)
            } else {
                errorMessage = error.userFriendlyMessage
                showError = true
            }
        }
        isLoading = false
    }
    
    func loadMembers() async {
        isLoadingMembers = true
        do {
            let response = try await APIService.shared.getHouseholdMembers()
            members = response.members
        } catch {
            errorMessage = error.userFriendlyMessage
            showError = true
        }
        isLoadingMembers = false
    }
}

@MainActor
class JoinHouseholdViewModel: ObservableObject {
    @Published var code = ""
    @Published var validationResult: InviteValidationResponse?
    @Published var isValidating = false
    @Published var isJoining = false
    @Published var showError = false
    @Published var showSuccess = false
    @Published var errorMessage = ""
    
    func validateCode() async {
        guard code.count == 6 else { return }
        
        isValidating = true
        validationResult = nil
        
        do {
            validationResult = try await APIService.shared.validateInviteCode(code)
        } catch {
            errorMessage = "Invalid or expired invite code"
            showError = true
        }
        
        isValidating = false
    }
    
    func joinHousehold() async {
        isJoining = true
        print("🔄 [JoinHouseholdViewModel] Attempting to join household with code: \(code)")
        
        do {
            let response = try await APIService.shared.joinHousehold(code: code)
            print("✅ [JoinHouseholdViewModel] Successfully joined household: \(response.household.id)")
            showSuccess = true
        } catch {
            print("❌ [JoinHouseholdViewModel] Failed to join: \(error)")
            errorMessage = error.userFriendlyMessage
            showError = true
        }
        
        isJoining = false
    }
}

#Preview {
    NavigationStack {
        HouseholdSharingView()
    }
}
