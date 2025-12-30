import Foundation

/// Persists the last used location per household to provide a sticky default
/// across barcode scanning and custom item adding flows.
@MainActor
class LastUsedLocationStore {
    static let shared = LastUsedLocationStore()
    
    private let userDefaults = UserDefaults.standard
    private let keyPrefix = "lastUsedLocation_"
    
    private init() {}
    
    /// Get the last used location ID for a household
    /// - Parameter householdId: The household ID (can be nil for users not in a household)
    /// - Returns: The last used location ID, or nil if never set
    func getLastLocation(for householdId: String?) -> String? {
        guard let householdId = householdId else { return nil }
        let key = keyPrefix + householdId
        return userDefaults.string(forKey: key)
    }
    
    /// Save the last used location ID for a household
    /// - Parameters:
    ///   - locationId: The location ID to persist
    ///   - householdId: The household ID (can be nil for users not in a household)
    func setLastLocation(_ locationId: String, for householdId: String?) {
        guard let householdId = householdId else { return }
        let key = keyPrefix + householdId
        userDefaults.set(locationId, forKey: key)
    }
    
    /// Clear the last used location for a household
    /// - Parameter householdId: The household ID
    func clearLastLocation(for householdId: String?) {
        guard let householdId = householdId else { return }
        let key = keyPrefix + householdId
        userDefaults.removeObject(forKey: key)
    }
    
    /// Get a safe default location ID, verifying it exists in the available locations
    /// - Parameters:
    ///   - householdId: The household ID
    ///   - availableLocations: The list of available locations
    ///   - defaultLocationId: The fallback location ID (usually "pantry")
    /// - Returns: A valid location ID from the available locations
    func getSafeDefaultLocation(
        for householdId: String?,
        availableLocations: [Location],
        defaultLocationId: String
    ) -> String {
        // Try to get last used location
        if let lastLocationId = getLastLocation(for: householdId),
           availableLocations.contains(where: { $0.id == lastLocationId }) {
            return lastLocationId
        }
        
        // Fall back to default (usually "pantry")
        if availableLocations.contains(where: { $0.id == defaultLocationId }) {
            // Update stored value to the fallback
            setLastLocation(defaultLocationId, for: householdId)
            return defaultLocationId
        }
        
        // Last resort: first available location
        if let firstLocation = availableLocations.first {
            setLastLocation(firstLocation.id, for: householdId)
            return firstLocation.id
        }
        
        // No locations available, return default anyway
        return defaultLocationId
    }
}
