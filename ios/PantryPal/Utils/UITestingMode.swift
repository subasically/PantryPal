import Foundation

/// Detects and configures UI testing mode
struct UITestingMode {
    
    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("UI_TESTING")
    }
    
    static var shouldDisableAppLock: Bool {
        ProcessInfo.processInfo.environment["UI_TEST_DISABLE_APP_LOCK"] == "true"
    }
    
    static var shouldInjectPremium: Bool {
        ProcessInfo.processInfo.environment["UI_TEST_INJECT_PREMIUM"] == "true"
    }
    
    static var apiBaseURL: String? {
        ProcessInfo.processInfo.environment["API_BASE_URL"]
    }
    
    static var testUserEmail: String {
        ProcessInfo.processInfo.environment["UI_TEST_EMAIL"] ?? "test@pantrypal.com"
    }
    
    static var testUserPassword: String {
        ProcessInfo.processInfo.environment["UI_TEST_PASSWORD"] ?? "Test123!"
    }
    
    /// Configure app for UI testing if needed
    static func configure() {
        #if DEBUG
        guard isUITesting else { return }
        
        print("🧪 [UITestingMode] UI Testing mode ENABLED")
        
        if shouldDisableAppLock {
            print("🧪 [UITestingMode] App lock DISABLED")
        }
        
        if shouldInjectPremium {
            print("🧪 [UITestingMode] Premium status INJECTED")
        }
        
        if let apiURL = apiBaseURL {
            print("🧪 [UITestingMode] API Base URL: \(apiURL)")
        }
        #endif
    }
}
