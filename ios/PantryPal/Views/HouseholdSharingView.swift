import SwiftUI
@preconcurrency import AVFoundation
import CoreImage.CIFilterBuiltins

struct HouseholdSharingView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = HouseholdSharingViewModel()
    @State private var showJoinSheet = false
    
    var body: some View {
        List {
            // Invite Section
            Section {
                if let invite = viewModel.currentInvite {
                    VStack(spacing: 16) {
                        // QR Code
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
                                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                                    .frame(width: 36, height: 44)
                                    .background(Color.ppPurple.opacity(0.2))
                                    .foregroundColor(Color.ppPrimary)
                                    .cornerRadius(8)
                            }
                        }
                        
                        Text("Expires in 24 hours")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Share Button
                        ShareLink(
                            item: "Join my PantryPal household '\(invite.householdName)' with code: \(invite.code)",
                            subject: Text("Join my PantryPal household"),
                            message: Text("Use this code to join: \(invite.code)")
                        ) {
                            Label("Share Invite", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.ppPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical)
                } else {
                    if !viewModel.isPremium {
                        Button {
                            NotificationCenter.default.post(name: .showPaywall, object: nil)
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
                                Image(systemName: "qrcode")
                                Text("Generate Invite Code")
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
                                    
                                    // Assume first member (creator) is owner
                                    if index == 0 {
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
                    
                    // Simplified code display
                    HStack(spacing: 8) {
                        ForEach(0..<6, id: \.self) { index in
                            CodeCharacterView(code: viewModel.code, index: index)
                        }
                    }
                    
                    TextField("Enter or paste code", text: $viewModel.code)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
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
                            Task {
                                await viewModel.joinHousehold()
                                if viewModel.showSuccess {
                                    onJoinSuccess?()
                                }
                            }
                        } label: {
                            Text("Join Household")
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

struct QRScannerView: UIViewControllerRepresentable {
    var onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController {
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?
    private var hasScanned = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .black
        setupCamera()
    }
    
    private func setupCamera() {
        let session = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoCaptureDevice),
              session.canAddInput(videoInput) else {
            return
        }
        
        session.addInput(videoInput)
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        }
        
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.layer.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        
        // Capture session is not Sendable, so we capture it weakly or use a local reference
        // but since we are in a class, we can just use [weak self] and access it, 
        // but self is MainActor isolated? No, UIViewController is MainActor.
        // The issue is capturing 'session' local variable in the closure.
        
        // Fix: Don't capture the local 'session' variable in the async closure.
        // Instead, use the property 'self.captureSession' but access it safely?
        // Actually, the best way is to just capture the session instance if we know what we are doing,
        // but Swift 6 is strict.
        
        // Let's try to just use the local variable but mark the closure as @Sendable (implicit in async)
        // and since AVCaptureSession is not Sendable, we get a warning.
        
        // Workaround: Create a separate start function or just ignore if we can't fix easily without major refactor.
        // But we can try to use a detached task or just keep it simple.
        
        // The error says: Capture of 'session' with non-Sendable type 'AVCaptureSession?' in a '@Sendable' closure
        
        // We can try to make the session start on a background queue without capturing the variable directly if possible?
        // No, we need the reference.
        
        // Let's use a helper method that takes the session.
        
        startSession(session)
        
        self.captureSession = session
        self.previewLayer = preview
    }
    
    private func startSession(_ session: AVCaptureSession) {
        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }
    
    private func stopSession() {
        guard let session = captureSession else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }
    
    func handleScannedCode(_ stringValue: String) {
        guard !hasScanned else { return }
        hasScanned = true
        stopSession()
        onCodeScanned?(stringValue)
    }
}

extension QRScannerViewController: @preconcurrency AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let metadataObject = metadataObjects.first,
              let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
              let stringValue = readableObject.stringValue else {
            return
        }
        
        handleScannedCode(stringValue)
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
            if error.localizedDescription.contains("Premium") {
                NotificationCenter.default.post(name: .showPaywall, object: nil)
            } else {
                errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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
        
        do {
            _ = try await APIService.shared.joinHousehold(code: code)
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
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
