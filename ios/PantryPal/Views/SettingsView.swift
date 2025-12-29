import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @EnvironmentObject private var notificationService: NotificationService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var biometricEnabled: Bool
    @State private var smartScannerEnabled: Bool
    @State private var appLockEnabled: Bool
    @State private var showingDisableAlert = false
    @State private var showingEnableError = false
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
        _appLockEnabled = State(initialValue: UserPreferences.shared.appLockEnabled)
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
                                Text(user.displayName)
                                    .font(.headline)
                                Text(user.email)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
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
                
                // Security Section
                if authViewModel.isBiometricAvailable {
                    Section("Security") {
                        if authViewModel.isPasswordLogin {
                            Toggle(isOn: Binding(
                                get: { biometricEnabled },
                                set: { newValue in
                                    if newValue {
                                        // Turning ON
                                        if authViewModel.hasPendingCredentials {
                                            authViewModel.enableBiometricLogin()
                                            biometricEnabled = true
                                        } else {
                                            biometricEnabled = false
                                            showingEnableError = true
                                        }
                                    } else {
                                        // Turning OFF
                                        biometricEnabled = false
                                        showingDisableAlert = true
                                    }
                                }
                            )) {
                                HStack {
                                    Image(systemName: authViewModel.biometricIcon)
                                        .foregroundColor(.ppPurple)
                                        .frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text("Use \(authViewModel.biometricName)")
                                        Text("Log in with \(authViewModel.biometricName)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        Toggle(isOn: Binding(
                            get: { appLockEnabled },
                            set: { newValue in
                                appLockEnabled = newValue
                                authViewModel.appLockEnabled = newValue
                            }
                        )) {
                            HStack {
                                Image(systemName: "lock.shield")
                                    .foregroundColor(.ppPurple)
                                    .frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text("Require \(authViewModel.biometricName) to Open")
                                    Text("Lock app when backgrounded")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
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
                    
                    Link(destination: URL(string: "https://world.openfoodfacts.org")!) {
                        HStack {
                            Text("Product data provided by Open Food Facts (ODbL)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
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
                                Label("Delete Household Data", systemImage: "trash.fill")
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
            .alert("Cannot Enable \(authViewModel.biometricName)", isPresented: $showingEnableError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("For security, please log out and log in again to enable \(authViewModel.biometricName).")
            }
            .alert("Delete Household Data?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Continue", role: .destructive) {
                    resetVerificationText = ""
                    showingResetVerification = true
                }
            } message: {
                Text("This action cannot be undone. All data will be wiped from all devices in your household.")
            }
            .alert("Verify Reset", isPresented: $showingResetVerification) {
                TextField("Type 'RESET'", text: $resetVerificationText)
                    .textInputAutocapitalization(.never)
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if resetVerificationText == "RESET" {
                        Task { await performReset() }
                    }
                }
                .disabled(resetVerificationText != "RESET")
            } message: {
                Text("Type 'RESET' to confirm.")
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
            // We fetch and delete individually to ensure the UI updates immediately.
            // Batch delete (modelContext.delete(model:)) operates on the store and leaves the context stale.
            let items = try modelContext.fetch(FetchDescriptor<SDInventoryItem>())
            for item in items { modelContext.delete(item) }
            
            let products = try modelContext.fetch(FetchDescriptor<SDProduct>())
            for product in products { modelContext.delete(product) }
            
            let locations = try modelContext.fetch(FetchDescriptor<SDLocation>())
            for location in locations { modelContext.delete(location) }
            
            let actions = try modelContext.fetch(FetchDescriptor<SDPendingAction>())
            for action in actions { modelContext.delete(action) }
            
            try modelContext.save()
            
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
