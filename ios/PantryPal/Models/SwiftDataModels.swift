import Foundation
import SwiftData

@Model
final class SDProduct {
    @Attribute(.unique) var id: String
    var upc: String?
    var name: String
    var brand: String?
    var details: String?
    var imageUrl: String?
    var category: String?
    var isCustom: Bool
    var householdId: String?
    
    // Relationship
    @Relationship(deleteRule: .cascade, inverse: \SDInventoryItem.product)
    var inventoryItems: [SDInventoryItem]?
    
    init(id: String, upc: String?, name: String, brand: String?, details: String?, imageUrl: String?, category: String?, isCustom: Bool, householdId: String?) {
        self.id = id
        self.upc = upc
        self.name = name
        self.brand = brand
        self.details = details
        self.imageUrl = imageUrl
        self.category = category
        self.isCustom = isCustom
        self.householdId = householdId
    }
}

@Model
final class SDLocation {
    @Attribute(.unique) var id: String
    var householdId: String
    var name: String
    var parentId: String?
    var level: Int
    var sortOrder: Int
    
    @Relationship(deleteRule: .nullify, inverse: \SDInventoryItem.location)
    var inventoryItems: [SDInventoryItem]?
    
    init(id: String, householdId: String, name: String, parentId: String?, level: Int, sortOrder: Int) {
        self.id = id
        self.householdId = householdId
        self.name = name
        self.parentId = parentId
        self.level = level
        self.sortOrder = sortOrder
    }
}

@Model
final class SDInventoryItem {
    @Attribute(.unique) var id: String
    var householdId: String
    var quantity: Int
    var expirationDate: Date?
    var notes: String?
    var createdAt: Date?
    var updatedAt: Date?
    
    var productId: String
    var locationId: String?
    
    @Relationship
    var product: SDProduct?
    
    @Relationship
    var location: SDLocation?
    
    init(id: String, householdId: String, quantity: Int, expirationDate: Date?, notes: String?, productId: String, locationId: String?) {
        self.id = id
        self.householdId = householdId
        self.quantity = quantity
        self.expirationDate = expirationDate
        self.notes = notes
        self.productId = productId
        self.locationId = locationId
    }
    
    var isExpired: Bool {
        guard let date = expirationDate else { return false }
        // Compare start of day to avoid time issues
        return Calendar.current.startOfDay(for: date) < Calendar.current.startOfDay(for: Date())
    }
    
    var isExpiringSoon: Bool {
        guard let date = expirationDate else { return false }
        let today = Calendar.current.startOfDay(for: Date())
        let itemDate = Calendar.current.startOfDay(for: date)
        
        guard let sevenDaysFromNow = Calendar.current.date(byAdding: .day, value: 7, to: today) else { return false }
        
        return itemDate <= sevenDaysFromNow && itemDate >= today
    }
    
    var displayName: String {
        product?.name ?? "Unknown Product"
    }
}
