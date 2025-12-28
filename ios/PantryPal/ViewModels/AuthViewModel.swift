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
    
    private var pendingCredentials: (email: String, password: String)?
    private let biometricService = BiometricAuthService.shared
    
    var isBiometricAvailable: Bool {
        biometricService.isBiometricAvailable
    }
    
    var isBiometricEnabled: Bool {
        biometricService.isBiometricLoginEnabled
    }
    
    var biometricName: String {
        biometricService.biometricName
    }
    
    var biometricIcon: String {
        biometricService.biometricIcon
    }
    
    var canUseBiometricLogin: Bool {
        biometricService.isBiometricAvailable && 
        biometricService.isBiometricLoginEnabled && 
        biometricService.hasStoredCredentials
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
        
        do {
            let response = try await APIService.shared.login(email: email, password: password)
            currentUser = response.user
            isAuthenticated = true
            
            // After successful login, prompt to enable biometrics if available and not already enabled
            if biometricService.isBiometricAvailable && !biometricService.isBiometricLoginEnabled {
                pendingCredentials = (email, password)
                showBiometricEnablePrompt = true
            }
            
            // Load full household info (for premium status)
            await loadCurrentUser()
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loginWithBiometrics() async {
        isLoading = true
        errorMessage = nil
        
        guard let credentials = await biometricService.authenticateWithBiometrics() else {
            errorMessage = "Biometric authentication failed"
            isLoading = false
            return
        }
        
        do {
            let response = try await APIService.shared.login(email: credentials.email, password: credentials.password)
            currentUser = response.user
            isAuthenticated = true
            
            // Load full household info
            await loadCurrentUser()
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        
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
                
                // Load full household info
                await loadCurrentUser()
            } catch let error as APIError {
                print("Apple Sign In API Error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            } catch {
                print("Apple Sign In Unknown Error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }
            
        case .failure(let error):
            print("Apple Sign In Failure: \(error.localizedDescription)")
            // Ignore cancellation error
            if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                errorMessage = error.localizedDescription
            }
        }
        
        isLoading = false
    }
    
    func enableBiometricLogin() {
        guard let credentials = pendingCredentials else { return }
        _ = biometricService.enableBiometricLogin(email: credentials.email, password: credentials.password)
        pendingCredentials = nil
    }
    
    func declineBiometricLogin() {
        pendingCredentials = nil
    }
    
    func disableBiometricLogin() {
        biometricService.disableBiometricLogin()
    }
    
    func register(email: String, password: String, name: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await APIService.shared.register(email: email, password: password, name: name)
            currentUser = response.user
            isAuthenticated = true
            showHouseholdSetup = true
            
            // Load full household info
            await loadCurrentUser()
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func completeHouseholdSetup() async {
        showHouseholdSetup = false
        // Refresh current user to ensure we have the latest household info
        await loadCurrentUser()
    }
    
    func logout() {
        APIService.shared.logout()
        currentUser = nil
        currentHousehold = nil
        isAuthenticated = false
    }
    
    func loadCurrentUser() async {
        do {
            let (user, household) = try await APIService.shared.getCurrentUser()
            currentUser = user
            currentHousehold = household
        } catch {
            logout()
        }
    }
}
