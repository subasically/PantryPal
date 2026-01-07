import SwiftUI
import SwiftData

struct HouseholdSetupView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var showJoinSheet = false
    @State private var householdName = ""
    @State private var isRenaming = false
    @State private var isCreating = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "house.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(LinearGradient.ppPrimaryGradient)
                    
                    Text("Welcome to PantryPal!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    
                    Text("Create your own household or join an existing one.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .padding(.top, 40)
                
                // Options
                VStack(spacing: 20) {
                    // Option 1: Create Household (Primary)
                    Button {
                        Task {
                            isCreating = true
                            await authViewModel.completeHouseholdSetup()
                            isCreating = false
                            authViewModel.showHouseholdSetup = false
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                if isCreating {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "house.fill")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                }
                                Text("Create my Household")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            Text("Start using your pantry right away.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.ppPurple)
                        .cornerRadius(16)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreating)
                    
                    // Option 2: Join Existing
                    Button {
                        showJoinSheet = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .font(.title2)
                                    .foregroundColor(.ppPurple)
                                Text("Join Household with invite code")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                            Text("Scan a QR code or enter an invite code.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(.quaternary, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isCreating)
                }
                .padding(.horizontal)
                
                if let errorMessage = authViewModel.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                Spacer(minLength: 40)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out", role: .destructive) {
                        authViewModel.logout()
                    }
                }
            }
            .sheet(isPresented: $showJoinSheet) {
                JoinHouseholdOnboardingView(onJoinSuccess: {
                    Task {
                        try? await SyncService.shared.syncFromRemote(modelContext: modelContext)
                    }
                })
            }
        }
    }
}

struct JoinHouseholdOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = JoinHouseholdViewModel()
    @State private var showScanner = false
    var onJoinSuccess: (() -> Void)?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Code Entry
                VStack(spacing: 12) {
                    Text("Enter Invite Code")
                        .font(.headline)
                    
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
                            Task {
                                print("🔘 [Onboarding] Join button tapped")
                                await viewModel.joinHousehold()
                                print("🔘 [Onboarding] joinHousehold completed, showSuccess: \(viewModel.showSuccess)")
                                
                                if viewModel.showSuccess {
                                    print("✅ [Onboarding] Join successful, clearing local cache...")
                                    
                                    // Clear local SwiftData cache from old household
                                    await clearLocalCache()
                                    
                                    print("✅ [Onboarding] Local cache cleared, syncing new household data...")
                                    onJoinSuccess?()
                                    
                                    print("🔘 [Onboarding] Calling completeHouseholdSetup...")
                                    await authViewModel.completeHouseholdSetup()
                                    print("✅ [Onboarding] Household setup completed")
                                    
                                    // After joining, hide the setup screen
                                    authViewModel.showHouseholdSetup = false
                                    print("🔘 [Onboarding] showHouseholdSetup set to false")
                                    
                                    print("🔘 [Onboarding] Dismissing sheet...")
                                    dismiss()
                                } else {
                                    print("❌ [Onboarding] Join failed or showSuccess is false")
                                }
                            }
                        } label: {
                            if viewModel.isJoining {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Join Household")
                                    .frame(maxWidth: .infinity)
                            }
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
        }
    }
    
    private func clearLocalCache() async {
        do {
            print("🗑️ [JoinHousehold] Clearing local SwiftData cache...")
            
            // Delete all local data from old household
            let items = try modelContext.fetch(FetchDescriptor<SDInventoryItem>())
            for item in items { modelContext.delete(item) }
            print("🗑️ [JoinHousehold] Deleted \(items.count) inventory items")
            
            let groceryItems = try modelContext.fetch(FetchDescriptor<SDGroceryItem>())
            for groceryItem in groceryItems { modelContext.delete(groceryItem) }
            print("🗑️ [JoinHousehold] Deleted \(groceryItems.count) grocery items")
            
            let products = try modelContext.fetch(FetchDescriptor<SDProduct>())
            for product in products { modelContext.delete(product) }
            print("🗑️ [JoinHousehold] Deleted \(products.count) products")
            
            let locations = try modelContext.fetch(FetchDescriptor<SDLocation>())
            for location in locations { modelContext.delete(location) }
            print("🗑️ [JoinHousehold] Deleted \(locations.count) locations")
            
            let actions = try modelContext.fetch(FetchDescriptor<SDPendingAction>())
            for action in actions { modelContext.delete(action) }
            print("🗑️ [JoinHousehold] Deleted \(actions.count) pending actions")
            
            try modelContext.save()
            print("✅ [JoinHousehold] Local cache cleared successfully")
            
            // Clear sync cursor so next sync starts fresh
            SyncCoordinator.shared.clearAllSyncState()
            print("✅ [JoinHousehold] Sync cursor reset")
            
        } catch {
            print("❌ [JoinHousehold] Error clearing local cache: \(error)")
        }
    }
}

#Preview {
    HouseholdSetupView()
        .environment(AuthViewModel())
}
