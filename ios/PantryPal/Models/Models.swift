import Foundation

// MARK: - User & Auth

struct User: Codable, Identifiable, Sendable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let householdId: String?
    
    var name: String {
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? "User" : fullName
    }
    
    var displayName: String {
        if !name.isEmpty && name != "Apple User" && name != "undefined undefined" && name != "User" {
            return name
        }
        if !email.isEmpty {
            return email
        }
        return "Member"
    }
}

struct AppConfig: Codable, Sendable {
    let freeLimit: Int?
}

struct AuthResponse: Codable, Sendable {
    let user: User
    let token: String
    let householdId: String?
}

struct LoginRequest: Codable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequest: Codable, Sendable {
    let email: String
    let password: String
    let firstName: String
    let lastName: String
}

// MARK: - Household

struct Household: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let createdAt: String?
    let isPremium: Bool?
    let premiumExpiresAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, isPremium
        case createdAt = "created_at"
        case premiumExpiresAt = "premiumExpiresAt"
    }
    
    // Helper to check if Premium is currently active (client-side validation)
    var isPremiumActive: Bool {
        guard let isPremium = isPremium, isPremium else {
            return false
        }
        
        // If no expiration date, Premium is active indefinitely
        guard let expiresAtString = premiumExpiresAt else {
            return true
        }
        
        // Check if expiration date is in the future
        let formatter = ISO8601DateFormatter()
        guard let expiresAt = formatter.date(from: expiresAtString) else {
            return isPremium // Fallback to isPremium if can't parse date
        }
        
        return expiresAt > Date()
    }
}

// MARK: - Product

struct Product: Codable, Identifiable, Sendable {
    let id: String
    let upc: String?
    let name: String
    let brand: String?
    let description: String?
    let imageUrl: String?
    let category: String?
    let isCustom: Bool
    let householdId: String?
    
    enum CodingKeys: String, CodingKey {
        case id, upc, name, brand, description, category
        case imageUrl = "image_url"
        case isCustom = "is_custom"
        case householdId = "household_id"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        upc = try container.decodeIfPresent(String.self, forKey: .upc)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decodeIfPresent(String.self, forKey: .brand)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        householdId = try container.decodeIfPresent(String.self, forKey: .householdId)
        
        // Handle is_custom as Int or Bool
        if let intValue = try? container.decode(Int.self, forKey: .isCustom) {
            isCustom = intValue != 0
        } else {
            isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(upc, forKey: .upc)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(brand, forKey: .brand)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encode(isCustom, forKey: .isCustom)
        try container.encodeIfPresent(householdId, forKey: .householdId)
    }
}

struct UPCLookupResponse: Codable, Sendable {
    let found: Bool
    let product: Product?
    let source: String?
    let upc: String?
    let requiresCustomProduct: Bool?
}

// MARK: - Inventory

struct InventoryItem: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let productId: String
    let householdId: String
    var locationId: String?
    var quantity: Int
    var expirationDate: String?
    var notes: String?
    let createdAt: String?
    let updatedAt: String?
    
    // Joined product fields
    let productName: String?
    let productBrand: String?
    let productUpc: String?
    let productImageUrl: String?
    let productCategory: String?
    
    // Joined location field
    let locationName: String?
    
    enum CodingKeys: String, CodingKey {
        case id, quantity, notes
        case productId = "product_id"
        case householdId = "household_id"
        case locationId = "location_id"
        case expirationDate = "expiration_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case productName = "product_name"
        case productBrand = "product_brand"
        case productUpc = "product_upc"
        case productImageUrl = "product_image_url"
        case productCategory = "product_category"
        case locationName = "location_name"
    }
    
    var displayName: String {
        productName ?? "Unknown Product"
    }
    
    var isExpired: Bool {
        guard let expDate = expirationDate else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: expDate) else { return false }
        return date < Date()
    }
    
    var isExpiringSoon: Bool {
        guard let expDate = expirationDate else { return false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: expDate) else { return false }
        let sevenDaysFromNow = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        return date <= sevenDaysFromNow && date >= Date()
    }
}

struct QuickAddRequest: Codable, Sendable {
    let upc: String
    let quantity: Int
    let expirationDate: String?
    let locationId: String
}

struct QuickAddResponse: Codable, Sendable {
    let item: InventoryItem?
    let action: String?
    let error: String?
    let requiresCustomProduct: Bool?
}

struct QuantityAdjustRequest: Codable, Sendable {
    let adjustment: Int
}

struct AdjustQuantityResponse: Codable, Sendable {
    // When item is updated (quantity > 0)
    let id: String?
    let productId: String?
    let householdId: String?
    let quantity: Int?
    let expirationDate: String?
    let notes: String?
    let createdAt: String?
    let updatedAt: String?
    let productName: String?
    let productBrand: String?
    let productUpc: String?
    let productImageUrl: String?
    
    // When item is deleted (quantity <= 0)
    let deleted: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, quantity, notes, deleted
        case productId = "product_id"
        case householdId = "household_id"
        case expirationDate = "expiration_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case productName = "product_name"
        case productBrand = "product_brand"
        case productUpc = "product_upc"
        case productImageUrl = "product_image_url"
    }
    
    var wasDeleted: Bool {
        deleted == true
    }
}

// MARK: - Sync

struct SyncChange: Codable, Sendable {
    let entityType: String
    let entityId: String
    let action: String
    let payloadString: String?
    let clientTimestamp: String
    
    enum CodingKeys: String, CodingKey {
        case entityType = "entity_type"
        case entityId = "entity_id"
        case action
        case payloadString = "payload"
        case clientTimestamp = "client_timestamp"
    }
    
    var payload: [String: Any]? {
        guard let payloadString = payloadString,
              let data = payloadString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }
}

struct ChangesResponse: Codable, Sendable {
    let changes: [SyncChange]
    let serverTime: String
}

struct FullSyncResponse: Codable, Sendable {
    let products: [Product]
    let inventory: [InventoryItem]
    let serverTime: String
}

// MARK: - Locations

struct Location: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let householdId: String
    let name: String
    let parentId: String?
    let level: Int
    let sortOrder: Int
    let createdAt: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, level
        case householdId = "household_id"
        case parentId = "parent_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct LocationFlat: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let fullPath: String
    let level: Int
    let parentId: String?
}

struct LocationsResponse: Codable, Sendable {
    let locations: [Location]
    let hierarchy: [LocationHierarchy]
}

struct LocationHierarchy: Codable, Sendable {
    let id: String
    let name: String
    let level: Int
    let children: [LocationHierarchy]
}

struct CreateLocationRequest: Codable, Sendable {
    let name: String
    let parentId: String?
}

// MARK: - Checkout

struct CheckoutScanRequest: Codable, Sendable {
    let upc: String
}

struct CheckoutScanResponse: Codable, Sendable, Equatable {
    let success: Bool?
    let message: String?
    let product: CheckoutProduct?
    let previousQuantity: Int?
    let newQuantity: Int?
    let itemDeleted: Bool?
    let inventoryItem: InventoryItem?
    let checkoutId: String?
    let addedToGrocery: Bool? // True if Premium auto-added to grocery
    let productName: String? // Full product name for grocery add prompt
    
    // Error responses
    let error: String?
    let found: Bool?
    let inStock: Bool?
    let upc: String?
}

struct CheckoutProduct: Codable, Sendable, Equatable {
    let id: String
    let name: String
    let brand: String?
    let imageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, brand
        case imageUrl = "imageUrl"
    }
}

struct CheckoutHistoryItem: Codable, Identifiable, Sendable {
    let id: String
    let inventoryId: String?
    let productId: String
    let householdId: String
    let userId: String
    let quantity: Int
    let checkedOutAt: String
    let productName: String
    let productBrand: String?
    let productImage: String?
    private let userNameRaw: String?
    
    // Computed property with fallback logic
    var userName: String {
        // If we have a valid name, use it
        if let name = userNameRaw, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        // Fallback to generic text
        return "Household member"
    }
    
    enum CodingKeys: String, CodingKey {
        case id, quantity
        case inventoryId = "inventory_id"
        case productId = "product_id"
        case householdId = "household_id"
        case userId = "user_id"
        case checkedOutAt = "checked_out_at"
        case productName = "product_name"
        case productBrand = "product_brand"
        case productImage = "product_image"
        case userNameRaw = "user_name"
    }
}

struct CheckoutHistoryResponse: Codable, Sendable {
    let history: [CheckoutHistoryItem]
    let pagination: Pagination
}

struct Pagination: Codable, Sendable {
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - Household Sharing

struct InviteCodeResponse: Codable, Sendable {
    let code: String
    let expiresAt: String
    let householdName: String
}

struct InviteValidationResponse: Codable, Sendable {
    let valid: Bool
    let householdId: String
    let householdName: String
    let memberCount: Int
    let expiresAt: String
}

struct JoinHouseholdResponse: Codable, Sendable {
    let success: Bool
    let household: Household
}

struct HouseholdMember: Codable, Identifiable, Sendable {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let createdAt: String
    
    var name: String {
        let fullName = "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
        return fullName.isEmpty ? "User" : fullName
    }
    
    var displayName: String {
        if !name.isEmpty && name != "Apple User" && name != "undefined undefined" && name != "User" {
            return name
        }
        if !email.isEmpty {
            return email
        }
        return "Member"
    }
}

struct HouseholdMembersResponse: Codable, Sendable {
    let members: [HouseholdMember]
}

struct ActiveInvite: Codable, Sendable {
    let code: String
    let expiresAt: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case code
        case expiresAt = "expires_at"
        case createdAt = "created_at"
    }
}

struct ActiveInvitesResponse: Codable, Sendable {
    let invites: [ActiveInvite]
}

// MARK: - Grocery

struct GroceryItem: Codable, Identifiable, Sendable {
    let id: Int
    let householdId: String
    let name: String
    let brand: String?
    let upc: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case householdId = "household_id"
        case name
        case brand
        case upc
        case createdAt = "created_at"
    }
    
    var displayName: String {
        if let brand = brand, !brand.isEmpty {
            return "\(brand) – \(name)"
        }
        return name
    }
    
    var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}
