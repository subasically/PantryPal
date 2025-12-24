import SwiftUI

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @EnvironmentObject private var notificationService: NotificationService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var biometricEnabled: Bool
    @State private var smartScannerEnabled: Bool
    @State private var showingDisableAlert = false
    @State private var showingResetConfirmation = false
    @State private var showingResetVerification = false
    @State private var resetVerificationText = ""
    @State private var isResetting = false
    @State private var resetError: String?
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
    
    init() {
        _biometricEnabled = State(initialValue: BiometricAuthService.shared.isBiometricLoginEnabled)
        _smartScannerEnabled = State(initialValue: UserPreferences.shared.useSmartScanner)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // User Info Section
                if let user = authViewModel.currentUser {
                    Section("Account") {
                        HStack {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.ppPurple)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                // Notifications Section
                Section("Notifications") {
                    if notificationService.isAuthorized {
                        HStack {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.ppGreen)
                                .frame(width: 24)
                            Text("Notifications enabled")
                                .foregroundColor(.secondary)
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.ppGreen)
                        }
                        
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "gear")
                                    .foregroundColor(.ppPurple)
                                    .frame(width: 24)
                                Text("Manage in Settings")
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "bell.slash.fill")
                                .foregroundColor(.ppOrange)
                                .frame(width: 24)
                            Text("Notifications disabled")
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            Task {
                                await notificationService.requestAuthorization()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "bell.fill")
                                    .foregroundColor(.ppPurple)
                                    .frame(width: 24)
                                Text("Enable Notifications")
                            }
                        }
                    }
                }
                
                // Scanner Section
                Section("Scanner") {
                    Toggle(isOn: $smartScannerEnabled) {
                        HStack {
                            Image(systemName: "text.viewfinder")
                                .foregroundColor(.ppPurple)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text("Smart Scanner")
                                Text("Multi-step flow with OCR for product name and expiration date")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onChange(of: smartScannerEnabled) { _, newValue in
                        UserPreferences.shared.useSmartScanner = newValue
                    }
                }
                
                // Security Section
                Section("Security") {
                    if authViewModel.isBiometricAvailable {
                        Toggle(isOn: $biometricEnabled) {
                            HStack {
                                Image(systemName: authViewModel.biometricIcon)
                                    .foregroundColor(.ppPurple)
                                    .frame(width: 24)
                                Text("Sign in with \(authViewModel.biometricName)")
                            }
                        }
                        .onChange(of: biometricEnabled) { oldValue, newValue in
                            if !newValue {
                                showingDisableAlert = true
                            }
                        }
                    } else {
                        HStack {
                            Image(systemName: "faceid")
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Biometric login not available")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Locations Section
                Section("Storage Locations") {
                    NavigationLink {
                        LocationsSettingsView()
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundColor(.ppGreen)
                                .frame(width: 24)
                            Text("Manage Locations")
                        }
                    }
                }
                
                // Household Section
                Section("Household") {
                    NavigationLink {
                        HouseholdSharingView()
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(.ppPurple)
                                .frame(width: 24)
                            Text("Household Sharing")
                        }
                    }
                }
                
                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Sign Out Section
                Section {
                    Button(role: .destructive) {
                        authViewModel.logout()
                        dismiss()
                    } label: {
                        HStack {
                            Spacer()
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            Spacer()
                        }
                    }
                }
                
                // Danger Zone
                Section {
                    Button(role: .destructive) {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            if isResetting {
                                ProgressView()
                                    .tint(.red)
                            } else {
                                Label("Reset All Data", systemImage: "trash.fill")
                            }
                            Spacer()
                        }
                    }
                    .disabled(isResetting)
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("This will permanently delete all inventory, history, and custom products for your household.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Disable \(authViewModel.biometricName)?", isPresented: $showingDisableAlert) {
                Button("Cancel", role: .cancel) {
                    biometricEnabled = true
                }
                Button("Disable", role: .destructive) {
                    authViewModel.disableBiometricLogin()
                }
            } message: {
                Text("You will need to enter your email and password to sign in.")
            }
            .alert("Reset All Data?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    resetVerificationText = ""
                    showingResetVerification = true
                }
            } message: {
                Text("This action cannot be undone. All data will be wiped from all devices in your household.")
            }
            .alert("Verify Reset", isPresented: $showingResetVerification) {
                TextField("Type 'delete all data'", text: $resetVerificationText)
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if resetVerificationText == "delete all data" {
                        Task { await performReset() }
                    }
                }
                .disabled(resetVerificationText != "delete all data")
            } message: {
                Text("Type 'delete all data' to confirm.")
            }
            .alert("Error", isPresented: Binding(get: { resetError != nil }, set: { if !$0 { resetError = nil } })) {
                Button("OK") { resetError = nil }
            } message: {
                Text(resetError ?? "Unknown error")
            }
        }
    }
    
    private func performReset() async {
        isResetting = true
        
        do {
            // 1. Call API to wipe server data
            try await APIService.shared.resetHouseholdData()
            
            // 2. Wipe local data
            try modelContext.delete(model: SDInventoryItem.self)
            try modelContext.delete(model: SDProduct.self)
            try modelContext.delete(model: SDLocation.self)
            try modelContext.delete(model: SDPendingAction.self)
            
            // 3. Re-sync to get default locations
            try await SyncService.shared.syncFromRemote(modelContext: modelContext)
            
            // 4. Success feedback
            HapticService.shared.success()
            dismiss()
        } catch {
            resetError = error.localizedDescription
            HapticService.shared.error()
        }
        
        isResetting = false
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
        .environmentObject(NotificationService.shared)
}
