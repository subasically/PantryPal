import Foundation

/// Manages user preferences stored in UserDefaults
@MainActor
final class UserPreferences: Sendable {
    static let shared = UserPreferences()
    
    private let defaults = UserDefaults.standard
    
    private enum Keys {
        static let lastUsedLocationId = "lastUsedLocationId"
    }
    
    private init() {}
    
    nonisolated var lastUsedLocationId: String? {
        get { UserDefaults.standard.string(forKey: Keys.lastUsedLocationId) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastUsedLocationId) }
    }
}
