import SwiftUI
import AuthenticationServices

@MainActor
@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var currentUser: User?
    var currentHousehold: Household?
    var isLoading = false
    var errorMessage: String?
    var showBiometricEnablePrompt = false
    var showHouseholdSetup = false
    var isSettingUpHousehold = false
    var hasLoggedOut = false
    var freeLimit: Int = 25
    var isAppLocked = false
    
    private var pendingCredentials: (email: String, password: String)?
    private var lastBackgroundedAt: Date?
    private let biometricService = BiometricAuthService.shared
    private let lastLoginMethodKey = "lastLoginMethod"
    
    var isBiometricAvailable: Bool {
        biometricService.isBiometricAvailable
    }
    
    var isBiometricEnabled: Bool {
        biometricService.isBiometricLoginEnabled
    }
    
    var appLockEnabled: Bool {
        get { UserPreferences.shared.appLockEnabled }
        set { UserPreferences.shared.appLockEnabled = newValue }
    }
    
    var isPasswordLogin: Bool {
        UserDefaults.standard.string(forKey: lastLoginMethodKey) == "password"
    }
    
    var biometricName: String {
        biometricService.biometricName
    }
    
    var biometricIcon: String {
        biometricService.biometricIcon
    }
    
    var canUseBiometricLogin: Bool {
        // Disable biometric login during UI testing
        guard !CommandLine.arguments.contains("--uitesting") else { return false }
        
        return biometricService.isBiometricAvailable && 
               biometricService.isBiometricLoginEnabled && 
               biometricService.hasStoredCredentials
    }
    
    var hasPendingCredentials: Bool {
        pendingCredentials != nil
    }
    
    init() {
        isAuthenticated = APIService.shared.isAuthenticated
        if isAuthenticated {
            Task { await loadCurrentUser() }
        }
    }
    
    func login(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        let startTime = Date()
        
        do {
            let response = try await APIService.shared.login(email: email, password: password)
            currentUser = response.user
            isAuthenticated = true
            
            // After successful login, prompt to enable biometrics if available and not already enabled
            if biometricService.isBiometricAvailable {
                if !biometricService.isBiometricLoginEnabled {
                    pendingCredentials = (email, password)
                    showBiometricEnablePrompt = true
                } else {
                    // Already enabled, update credentials in case password changed
                    _ = biometricService.enableBiometricLogin(email: email, password: password)
                }
            }
            
            UserDefaults.standard.set("password", forKey: lastLoginMethodKey)
            
            // Load full household info (for premium status)
            await loadCurrentUser()
            
            // Auto-create household if user doesn't have one
            if currentHousehold == nil {
                isSettingUpHousehold = true
                await completeHouseholdSetup()
                isSettingUpHousehold = false
            }
            
            // Only show household setup if user still doesn't have one (creation failed or needs to join)
            if currentHousehold == nil {
                showHouseholdSetup = true
            } else {
                showHouseholdSetup = false
            }
        } catch let error as APIError {
            errorMessage = error.userFriendlyMessage
        } catch {
            errorMessage = error.userFriendlyMessage
        }
        
        // Ensure minimum loading time of 1.5 seconds
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 1.5 {
            try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
        }
        
        isLoading = false
    }
    
    func loginWithBiometrics() async {
        isLoading = true
        errorMessage = nil
        let startTime = Date()
        
        guard let credentials = await biometricService.authenticateWithBiometrics() else {
            errorMessage = "Biometric authentication failed"
            isLoading = false
            return
        }
        
        // Store credentials to allow re-enabling if disabled
        pendingCredentials = credentials
        
        do {
            let response = try await APIService.shared.login(email: credentials.email, password: credentials.password)
            currentUser = response.user
            isAuthenticated = true
            
            UserDefaults.standard.set("password", forKey: lastLoginMethodKey)
            
            // Load full household info
            await loadCurrentUser()
            
            // Auto-create household if user doesn't have one
            if currentHousehold == nil {
                await completeHouseholdSetup()
            }
            
            // Only show household setup if user still doesn't have one (creation failed or needs to join)
            if currentHousehold == nil {
                showHouseholdSetup = true
            }
        } catch let error as APIError {
            errorMessage = error.userFriendlyMessage
        } catch {
            errorMessage = error.userFriendlyMessage
        }
        
        // Ensure minimum loading time of 1.5 seconds
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 1.5 {
            try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
        }
        
        isLoading = false
    }
    
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        let startTime = Date()
        
        print("Starting Apple Sign In...")
        
        switch result {
        case .success(let auth):
            guard let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                print("Apple Sign In Error: Invalid credentials or missing identity token")
                errorMessage = "Invalid Apple ID credentials"
                isLoading = false
                return
            }
            
            let email = appleIDCredential.email
            let name = appleIDCredential.fullName
            
            print("Apple Sign In: Got identity token. Email: \(String(describing: email))")
            
            do {
                let response = try await APIService.shared.loginWithApple(
                    identityToken: identityToken,
                    email: email,
                    name: name
                )
                print("Apple Sign In: API success. User: \(response.user.id)")
                currentUser = response.user
                isAuthenticated = true
                
                UserDefaults.standard.set("apple", forKey: lastLoginMethodKey)
                
                // Load full household info
                await loadCurrentUser()
                
                // Auto-create household if user doesn't have one
                if currentHousehold == nil {
                    isSettingUpHousehold = true
                    await completeHouseholdSetup()
                    isSettingUpHousehold = false
                }
                
                // Only show household setup if user still doesn't have one (creation failed or needs to join)
                if currentHousehold == nil {
                    showHouseholdSetup = true
                } else {
                    showHouseholdSetup = false
                }
            } catch let error as APIError {
                print("Apple Sign In API Error: \(error.localizedDescription)")
                errorMessage = error.userFriendlyMessage
            } catch {
                print("Apple Sign In Unknown Error: \(error.localizedDescription)")
                errorMessage = error.userFriendlyMessage
            }
            
        case .failure(let error):
            print("Apple Sign In Failure: \(error.localizedDescription)")
            // Ignore cancellation error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.userFriendlyMessage
            }
        }
        
        // Ensure minimum loading time of 1.5 seconds
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 1.5 {
            try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
        }
        
        isLoading = false
    }
    
    func enableBiometricLogin() {
        guard let credentials = pendingCredentials else { return }
        _ = biometricService.enableBiometricLogin(email: credentials.email, password: credentials.password)
        // Keep pendingCredentials to allow toggling off and on without re-login
    }
    
    func declineBiometricLogin() {
        // Just dismiss the prompt, but keep credentials in case user wants to enable later in Settings
        showBiometricEnablePrompt = false
    }
    
    func disableBiometricLogin() {
        biometricService.disableBiometricLogin()
    }
    
    func register(email: String, password: String, firstName: String, lastName: String) async {
        isLoading = true
        errorMessage = nil
        let startTime = Date()
        
        do {
            let response = try await APIService.shared.register(email: email, password: password, firstName: firstName, lastName: lastName)
            currentUser = response.user
            isAuthenticated = true
            
            // Store credentials temporarily to allow enabling biometrics
            if biometricService.isBiometricAvailable && !biometricService.isBiometricLoginEnabled {
                pendingCredentials = (email, password)
                // We don't auto-prompt here to avoid interrupting the onboarding flow (household setup)
                // But the option will now be visible in Settings
            }
            
            UserDefaults.standard.set("password", forKey: lastLoginMethodKey)
            
            // Load full household info
            await loadCurrentUser()
            
            // Auto-create household if user doesn't have one
            if currentHousehold == nil {
                isSettingUpHousehold = true
                await completeHouseholdSetup()
                isSettingUpHousehold = false
            }
            
            // Only show household setup if user still doesn't have one (creation failed or needs to join)
            if currentHousehold == nil {
                showHouseholdSetup = true
            } else {
                showHouseholdSetup = false
            }
        } catch let error as APIError {
            errorMessage = error.userFriendlyMessage
        } catch {
            errorMessage = error.userFriendlyMessage
        }
        
        // Ensure minimum loading time of 1.5 seconds
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 1.5 {
            try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
        }
        
        isLoading = false
    }
    
    func completeHouseholdSetup() async {
        print("🔄 [AuthViewModel] completeHouseholdSetup called, currentHousehold: \(currentHousehold?.id ?? "nil")")
        
        // Refresh current user first to get latest household info
        await loadCurrentUser()
        print("🔄 [AuthViewModel] After refresh, currentHousehold: \(currentHousehold?.id ?? "nil")")
        
        // Only create a household if user still doesn't have one after refresh
        if currentHousehold == nil {
            do {
                _ = try await APIService.shared.createHousehold()
                print("✅ [AuthViewModel] Created new household")
                await loadCurrentUser()
            } catch {
                print("❌ [AuthViewModel] Failed to create household: \(error)")
                errorMessage = "Failed to create household. Please try again or contact support."
                // Return early if creation failed - don't dismiss setup screen
                return
            }
        }
        
        // Always ensure locations exist (handles both new households and existing households with deleted locations)
        await ensureDefaultLocationsExist()
        
        print("✅ [AuthViewModel] Household setup completed, user household: \(currentHousehold?.id ?? "nil")")
        
        // Don't auto-dismiss - let user choose to join existing or continue with created household
    }
    
    /// Ensure default locations exist - creates them if missing (idempotent)
    private func ensureDefaultLocationsExist() async {
        do {
            // Check if locations already exist
            let locations = try await APIService.shared.getLocations()
            
            if locations.isEmpty {
                print("📍 [AuthViewModel] No locations found, creating defaults...")
                await createDefaultLocations()
            } else {
                print("✅ [AuthViewModel] Found \(locations.count) existing locations, skipping creation")
            }
        } catch {
            print("⚠️ [AuthViewModel] Failed to check existing locations: \(error)")
            // Try to create anyway - API will handle duplicates
            await createDefaultLocations()
        }
    }
    
    /// Create default locations for a new household (client-managed)
    private func createDefaultLocations() async {
        let defaultLocations = [
            "Pantry",
            "Fridge",
            "Freezer",
            "Cabinet",
            "Garage",
            "Basement",
            "Other"
        ]
        
        print("📍 [AuthViewModel] Creating \(defaultLocations.count) default locations")
        
        do {
            for location in defaultLocations {
                _ = try await APIService.shared.createLocation(name: location, parentId: nil)
            }
            print("✅ [AuthViewModel] Successfully created all default locations")
        } catch {
            print("⚠️ [AuthViewModel] Failed to create default locations: \(error)")
            // Non-fatal - user can still use the app and create locations manually
        }
    }
    
    func logout() {
        APIService.shared.logout()
        currentUser = nil
        currentHousehold = nil
        isAuthenticated = false
        hasLoggedOut = true
        pendingCredentials = nil
    }
    
    func loadCurrentUser() async {
        do {
            let (user, household, config) = try await APIService.shared.getCurrentUser()
            currentUser = user
            currentHousehold = household
            
            if let limit = config?.freeLimit {
                freeLimit = limit
            }
            
            // If user has no household, show setup
            if household == nil {
                showHouseholdSetup = true
            }
        } catch {
            logout()
        }
    }
    
    func refreshCurrentUser() async {
        // Force refresh user/household data (used after premium upgrade simulation)
        await loadCurrentUser()
    }
    
    // MARK: - App Lock
    
    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lastBackgroundedAt = Date()
        case .active:
            checkAppLock()
        default:
            break
        }
    }
    
    private func checkAppLock() {
        guard appLockEnabled, isBiometricAvailable else { return }
        
        // If already locked, do nothing
        if isAppLocked { return }
        
        // Check grace period or cold launch
        let shouldLock: Bool
        if let lastBackgroundedAt = lastBackgroundedAt {
            let elapsed = Date().timeIntervalSince(lastBackgroundedAt)
            shouldLock = elapsed > 30
        } else {
            // Cold launch
            shouldLock = true
        }
        
        if shouldLock {
            isAppLocked = true
            // Attempt unlock immediately
            Task {
                await unlockApp()
            }
        }
    }
    
    func unlockApp() async {
        guard isAppLocked else { return }
        
        let success = await biometricService.authenticateUser()
        if success {
            isAppLocked = false
            lastBackgroundedAt = Date() // Reset to now to prevent immediate re-lock
        }
    }
}
