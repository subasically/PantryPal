import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @EnvironmentObject private var notificationService: NotificationService
    @EnvironmentObject private var confettiCenter: ConfettiCenter
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
    @State private var showingPaywall = false
    
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
    
    // MARK: - Body Sections
    
    @ViewBuilder
    private var accountSection: some View {
        if let user = authViewModel.currentUser {
            Section("Account") {
                accountRow(for: user)
            }
        }
    }
    
    @ViewBuilder
    private var premiumSection: some View {
        if authViewModel.currentHousehold?.isPremiumActive != true {
            premiumUpgradeSection
        }
    }
    
    private var householdSection: some View {
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
    }
    
    private var notificationsSection: some View {
        Section {
            if let household = authViewModel.currentHousehold, household.isPremiumActive {
                // Premium users see notification toggle
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
            } else {
                // Free users see Premium upsell
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.ppPurple)
                            .frame(width: 24)
                        Text("Smart Notifications")
                    }
                    Text("Get alerts 7, 3, and 1 day before items expire. Upgrade to Premium to unlock.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Notifications")
        }
    }
    
    @ViewBuilder
    private var securitySection: some View {
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
    }
    
    private var debugSection: some View {
        Section {
            Button {
                Task {
                    // Clear sync state completely (UserDefaults + in-memory)
                    SyncCoordinator.shared.clearAllSyncState()
                    
                    // Clear any stale pending actions with invalid locations
                    let actions = try? modelContext.fetch(FetchDescriptor<SDPendingAction>())
                    if let actions = actions {
                        for action in actions {
                            modelContext.delete(action)
                        }
                        try? modelContext.save()
                        print("🧹 [Debug] Cleared \(actions.count) pending actions")
                    }
                    
                    // Force immediate full sync
                    await SyncCoordinator.shared.syncNow(
                        householdId: authViewModel.currentUser?.householdId,
                        modelContext: modelContext,
                        reason: .bootstrap
                    )
                    
                    ToastCenter.shared.show("Full sync completed", type: .success)
                }
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundColor(.blue)
                        .frame(width: 24)
                    Text("Force Full Sync Now")
                }
            }
            
            Button {
                Task {
                    do {
                        // Call server to simulate premium with far-future expiration
                        let futureDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())!
                        let formatter = ISO8601DateFormatter()
                        let expiresAt = formatter.string(from: futureDate)
                        
                        let validationData: [String: Any] = [
                            "transactionId": "debug_\(UUID().uuidString)",
                            "productId": "com.pantrypal.premium.annual",
                            "originalTransactionId": "debug_original",
                            "expiresAt": expiresAt
                        ]
                        
                        let response = try await APIService.shared.validateReceipt(validationData)
                        authViewModel.currentHousehold = response.household
                        
                        ToastCenter.shared.show("Premium activated (1 year)", type: .success)
                        confettiCenter.celebrate(duration: 3.0)
                        
                        print("🎉 [Debug] Simulated premium with expiration: \(expiresAt)")
                    } catch {
                        ToastCenter.shared.show("Failed to simulate premium", type: .error)
                        print("❌ [Debug] Failed to simulate premium: \(error)")
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "star.circle.fill")
                        .foregroundColor(.ppOrange)
                        .frame(width: 24)
                    Text("Simulate Premium (1 Year)")
                }
            }
        } header: {
            Text("Debug")
        } footer: {
            Text("Force sync clears cursor and syncs. Simulate Premium adds 1-year subscription for testing (sandbox subscriptions expire in 1 hour).")
        }
    }
    
    private var aboutSection: some View {
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
    }
    
    private var supportSection: some View {
        Section("Support") {
            Link(destination: URL(string: "mailto:webalenko@icloud.com?subject=PantryPal Support Request")!) {
                HStack {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.ppPurple)
                        .frame(width: 24)
                    Text("Report an Issue")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    private var signOutSection: some View {
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
            .accessibilityIdentifier("settings.signOutButton")
        }
    }
    
    private var dangerZoneSection: some View {
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
    
    var body: some View {
        NavigationStack {
            settingsList
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .environment(authViewModel)
                .environmentObject(confettiCenter)
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
    
    private var settingsList: some View {
        List {
            accountSection
            premiumSection
            householdSection
            notificationsSection
            securitySection
            debugSection
            supportSection
            aboutSection
            signOutSection
            dangerZoneSection
        }
        .accessibilityIdentifier("settings.list")
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button("Done") {
                dismiss()
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
            
            let groceryItems = try modelContext.fetch(FetchDescriptor<SDGroceryItem>())
            for groceryItem in groceryItems { modelContext.delete(groceryItem) }
            
            let products = try modelContext.fetch(FetchDescriptor<SDProduct>())
            for product in products { modelContext.delete(product) }
            
            let locations = try modelContext.fetch(FetchDescriptor<SDLocation>())
            for location in locations { modelContext.delete(location) }
            
            let actions = try modelContext.fetch(FetchDescriptor<SDPendingAction>())
            for action in actions { modelContext.delete(action) }
            
            try modelContext.save()
            
            // 3. Re-sync to get default locations
            try await SyncService.shared.syncFromRemote(modelContext: modelContext)
            
            // 4. Post notification to refresh inventory view
            await MainActor.run {
                NotificationCenter.default.post(name: NSNotification.Name("householdDataDeleted"), object: nil)
            }
            
            // 5. Success feedback
            HapticService.shared.success()
            ToastCenter.shared.show("All household data deleted", type: .success)
            dismiss()
        } catch {
            resetError = error.localizedDescription
            HapticService.shared.error()
        }
        
        isResetting = false
    }
    
    // MARK: - Helper Views
    
    private func accountRow(for user: User) -> some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.ppPurple)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(user.displayName)
                        .font(.headline)
                    
                    statusBadge
                }
                
                Text(user.email)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var statusBadge: some View {
        if authViewModel.currentHousehold?.isPremiumActive == true {
            Text("Premium")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    LinearGradient(
                        colors: [.ppPurple, .ppBlue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(6)
        } else {
            Text("Free")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(.systemGray5))
                .cornerRadius(6)
        }
    }
    
    private var premiumUpgradeSection: some View {
        Section {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "crown.fill")
                        .font(.title3)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.ppPurple, .ppBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upgrade to Premium")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("Unlimited items & household sharing")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthViewModel())
        .environmentObject(NotificationService.shared)
}
