import SwiftUI
import AuthenticationServices

@MainActor
@Observable
final class AuthViewModel {
    var isAuthenticated = false
    var currentUser: User?
    var isLoading = false
    var errorMessage: String?
    var showBiometricEnablePrompt = false
    
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
        
        switch result {
        case .success(let auth):
            guard let appleIDCredential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let identityTokenData = appleIDCredential.identityToken,
                  let identityToken = String(data: identityTokenData, encoding: .utf8) else {
                errorMessage = "Invalid Apple ID credentials"
                isLoading = false
                return
            }
            
            let email = appleIDCredential.email
            let name = appleIDCredential.fullName
            
            do {
                let response = try await APIService.shared.loginWithApple(
                    identityToken: identityToken,
                    email: email,
                    name: name
                )
                currentUser = response.user
                isAuthenticated = true
            } catch let error as APIError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
            
        case .failure(let error):
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
    
    func register(email: String, password: String, name: String, householdName: String? = nil, householdId: String? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await APIService.shared.register(email: email, password: password, name: name, householdName: householdName, householdId: householdId)
            currentUser = response.user
            isAuthenticated = true
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func logout() {
        APIService.shared.logout()
        currentUser = nil
        isAuthenticated = false
    }
    
    func loadCurrentUser() async {
        do {
            currentUser = try await APIService.shared.getCurrentUser()
        } catch {
            logout()
        }
    }
}
