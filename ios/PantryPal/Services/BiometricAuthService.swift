import LocalAuthentication
import SwiftUI

@MainActor
final class BiometricAuthService {
    static let shared = BiometricAuthService()
    
    private let context = LAContext()
    private let keychainService = "com.pantrypal.biometric"
    
    enum BiometricType {
        case none
        case faceID
        case touchID
    }
    
    var biometricType: BiometricType {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
            return .none
        }
        
        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .none
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }
    
    var isBiometricAvailable: Bool {
        biometricType != .none
    }
    
    var biometricName: String {
        switch biometricType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return "Biometrics"
        }
    }
    
    var biometricIcon: String {
        switch biometricType {
        case .faceID:
            return "faceid"
        case .touchID:
            return "touchid"
        case .none:
            return "lock"
        }
    }
    
    // Check if biometric login is enabled
    var isBiometricLoginEnabled: Bool {
        UserDefaults.standard.bool(forKey: "biometricLoginEnabled")
    }
    
    // Check if we have stored credentials
    var hasStoredCredentials: Bool {
        getStoredEmail() != nil && getStoredPassword() != nil
    }
    
    // Enable biometric login and store credentials
    func enableBiometricLogin(email: String, password: String) -> Bool {
        guard saveCredentials(email: email, password: password) else {
            return false
        }
        UserDefaults.standard.set(true, forKey: "biometricLoginEnabled")
        return true
    }
    
    // Disable biometric login
    func disableBiometricLogin() {
        deleteCredentials()
        UserDefaults.standard.set(false, forKey: "biometricLoginEnabled")
    }
    
    // Authenticate with biometrics and return credentials
    func authenticateWithBiometrics() async -> (email: String, password: String)? {
        let context = LAContext()
        context.localizedCancelTitle = "Use Password"
        
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return nil
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Log in to PantryPal"
            )
            
            if success, let email = getStoredEmail(), let password = getStoredPassword() {
                return (email, password)
            }
        } catch {
            print("Biometric authentication failed: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    // MARK: - Keychain Operations
    
    private func saveCredentials(email: String, password: String) -> Bool {
        // Save email
        let emailSaved = saveToKeychain(key: "email", value: email)
        // Save password
        let passwordSaved = saveToKeychain(key: "password", value: password)
        
        return emailSaved && passwordSaved
    }
    
    private func getStoredEmail() -> String? {
        return getFromKeychain(key: "email")
    }
    
    private func getStoredPassword() -> String? {
        return getFromKeychain(key: "password")
    }
    
    private func deleteCredentials() {
        deleteFromKeychain(key: "email")
        deleteFromKeychain(key: "password")
    }
    
    private func saveToKeychain(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        
        // Delete existing item first
        deleteFromKeychain(key: key)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
