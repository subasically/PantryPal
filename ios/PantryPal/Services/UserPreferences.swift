import Foundation

/// Manages user preferences stored in UserDefaults
@MainActor
final class UserPreferences: Sendable {
    static let shared = UserPreferences()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let lastUsedLocationId = "lastUsedLocationId"
        static let useSmartScanner = "useSmartScanner"
    }
    
    private init() {}
    
    nonisolated var lastUsedLocationId: String? {
        get { UserDefaults.standard.string(forKey: Keys.lastUsedLocationId) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastUsedLocationId) }
    }
    
    nonisolated var useSmartScanner: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.useSmartScanner) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.useSmartScanner) }
    }
}
