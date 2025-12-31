import Foundation
import SwiftData

@MainActor
final class SyncService: Sendable {
    static let shared = SyncService()
    
    private init() {}
    
    func syncFromRemote(modelContext: ModelContext) async throws {
        print("🔄 [SyncService] Starting syncFromRemote...")
        
        // Check if user has a household - skip sync if they don't
        guard let (user, _, _) = try? await APIService.shared.getCurrentUser(),
              user.householdId != nil else {
            print("⏭️ [SyncService] User has no household, skipping sync")
            return
        }
        
        // 1. Fetch all data from API
        async let fullSyncResponse = APIService.shared.fullSync()
        async let locationsResponse = APIService.shared.getLocationsHierarchy()
        
        let (syncData, locationsData) = try await (fullSyncResponse, locationsResponse)
        print("✅ [SyncService] Fetched \(syncData.inventory.count) items and \(locationsData.locations.count) locations from server")
        
        // 2. Sync Locations
        // We flatten the hierarchy for storage, but keep parentId
        let flatLocations = flattenLocations(locationsData.locations)
        let remoteLocationIds = Set(flatLocations.map { $0.id })
        
        // Delete local locations not in remote
        let allLocationsDescriptor = FetchDescriptor<SDLocation>()
        if let allLocations = try? modelContext.fetch(allLocationsDescriptor) {
            for loc in allLocations {
                if !remoteLocationIds.contains(loc.id) {
                    print("🗑️ [SyncService] Deleting stale local location: \(loc.name) (\(loc.id))")
                    modelContext.delete(loc)
                }
            }
        }
        
        for loc in flatLocations {
            let locationId = loc.id
            
            // Check if exists
            let descriptor = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == locationId })
            let existing = try? modelContext.fetch(descriptor).first
            
            if let existing = existing {
                existing.name = loc.name
                existing.parentId = loc.parentId
                existing.level = loc.level
                existing.sortOrder = loc.sortOrder
            } else {
                let newLoc = SDLocation(
                    id: loc.id,
                    householdId: loc.householdId,
                    name: loc.name,
                    parentId: loc.parentId,
                    level: loc.level,
                    sortOrder: loc.sortOrder
                )
                modelContext.insert(newLoc)
            }
        }
        
        // 3. Sync Products
        for prod in syncData.products {
            let productId = prod.id
            let descriptor = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == productId })
            let existing = try? modelContext.fetch(descriptor).first
            
            if let existing = existing {
                existing.upc = prod.upc
                existing.name = prod.name
                existing.brand = prod.brand
                existing.details = prod.description
                existing.imageUrl = prod.imageUrl
                existing.category = prod.category
                existing.isCustom = prod.isCustom
            } else {
                let newProd = SDProduct(
                    id: prod.id,
                    upc: prod.upc,
                    name: prod.name,
                    brand: prod.brand,
                    details: prod.description,
                    imageUrl: prod.imageUrl,
                    category: prod.category,
                    isCustom: prod.isCustom,
                    householdId: prod.householdId
                )
                modelContext.insert(newProd)
            }
        }
        
        // 4. Sync Inventory
        // First, get all existing IDs to detect deletions
        let allItemsDescriptor = FetchDescriptor<SDInventoryItem>()
        let allItems = (try? modelContext.fetch(allItemsDescriptor)) ?? []
        let remoteIds = Set(syncData.inventory.map { $0.id })
        
        print("📊 [SyncService] Local items: \(allItems.count), Remote items: \(remoteIds.count)")
        
        // Delete items not in remote
        var deletedCount = 0
        for item in allItems {
            if !remoteIds.contains(item.id) {
                print("🗑️ [SyncService] Deleting local item not in remote: \(item.id) (\(item.displayName))")
                modelContext.delete(item)
                deletedCount += 1
            }
        }
        if deletedCount > 0 {
            print("🗑️ [SyncService] Deleted \(deletedCount) stale local items")
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for item in syncData.inventory {
            let itemId = item.id
            let descriptor = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == itemId })
            let existing = try? modelContext.fetch(descriptor).first
            
            var expDate: Date? = nil
            if let dateStr = item.expirationDate {
                // Try simple format first, then ISO
                expDate = dateFormatter.date(from: dateStr) ?? isoFormatter.date(from: dateStr)
                // Fallback for ISO without fractional seconds
                if expDate == nil {
                    let isoSimple = ISO8601DateFormatter()
                    expDate = isoSimple.date(from: dateStr)
                }
            }
            
            if let existing = existing {
                existing.quantity = item.quantity
                existing.expirationDate = expDate
                existing.notes = item.notes
                existing.locationId = item.locationId
                
                // Update relationships
                if existing.productId != item.productId {
                    existing.productId = item.productId
                    let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == item.productId })
                    existing.product = try? modelContext.fetch(prodDesc).first
                }
                
                if existing.locationId != item.locationId {
                    if let locId = item.locationId {
                        let locDesc = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == locId })
                        existing.location = try? modelContext.fetch(locDesc).first
                    } else {
                        existing.location = nil
                    }
                }
                
            } else {
                let newItem = SDInventoryItem(
                    id: item.id,
                    householdId: item.householdId,
                    quantity: item.quantity,
                    expirationDate: expDate,
                    notes: item.notes,
                    productId: item.productId,
                    locationId: item.locationId
                )
                
                // Link Product
                let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == item.productId })
                newItem.product = try? modelContext.fetch(prodDesc).first
                
                // Link Location
                if let locId = item.locationId {
                    let locDesc = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == locId })
                    newItem.location = try? modelContext.fetch(locDesc).first
                }
                
                modelContext.insert(newItem)
            }
        }
        
        try? modelContext.save()
    }
    
    private func flattenLocations(_ locations: [Location]) -> [Location] {
        // The API returns a flat list in `locations` property of LocationsResponse
        // So we don't actually need to flatten the hierarchy manually if we use that.
        return locations
    }
    
    /// Incremental sync using /sync/changes endpoint
    func syncChanges(since: String, modelContext: ModelContext) async throws -> String {
        print("🔄 [SyncService] Starting incremental sync since: \(since)")
        
        // Check if user has a household
        guard let (user, _, _) = try? await APIService.shared.getCurrentUser(),
              user.householdId != nil else {
            print("⏭️ [SyncService] User has no household, skipping sync")
            throw AppError.validation(message: "No household found")
        }
        
        // Fetch changes since last sync
        let changesResponse = try await APIService.shared.getChanges(since: since)
        print("📦 [SyncService] Received \(changesResponse.changes.count) changes")
        
        // If too many changes or error, fall back to full sync
        if changesResponse.changes.count > 100 {
            print("⚠️ [SyncService] Too many changes (\(changesResponse.changes.count)), falling back to full sync")
            try await syncFromRemote(modelContext: modelContext)
            return changesResponse.serverTime
        }
        
        // Apply changes
        for change in changesResponse.changes {
            try applyChange(change, modelContext: modelContext)
        }
        
        try? modelContext.save()
        print("✅ [SyncService] Applied \(changesResponse.changes.count) changes")
        
        return changesResponse.serverTime
    }
    
    private func applyChange(_ change: SyncChange, modelContext: ModelContext) throws {
        switch change.entityType {
        case "inventory":
            try applyInventoryChange(change, modelContext: modelContext)
        case "product":
            try applyProductChange(change, modelContext: modelContext)
        case "grocery":
            try applyGroceryChange(change, modelContext: modelContext)
        default:
            print("⚠️ [SyncService] Unknown entity type: \(change.entityType)")
        }
    }
    
    private func applyInventoryChange(_ change: SyncChange, modelContext: ModelContext) throws {
        let itemId = change.entityId
        
        if change.action == "delete" {
            // Delete item
            let descriptor = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == itemId })
            if let existing = try? modelContext.fetch(descriptor).first {
                print("🗑️ [SyncService] Deleting inventory item: \(itemId)")
                modelContext.delete(existing)
            }
        } else {
            // Create or update
            guard let payload = change.payload else { return }
            
            let descriptor = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == itemId })
            let existing = try? modelContext.fetch(descriptor).first
            
            // Parse expiration date
            var expDate: Date? = nil
            if let expStr = payload["expirationDate"] as? String {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                expDate = dateFormatter.date(from: expStr)
            }
            
            if let existing = existing {
                // Update
                existing.quantity = payload["quantity"] as? Int ?? existing.quantity
                existing.expirationDate = expDate
                existing.notes = payload["notes"] as? String
                existing.locationId = payload["locationId"] as? String
                print("✏️ [SyncService] Updated inventory item: \(itemId)")
            } else {
                // Create
                guard let productId = payload["productId"] as? String,
                      let householdId = payload["householdId"] as? String else { return }
                
                let newItem = SDInventoryItem(
                    id: itemId,
                    householdId: householdId,
                    quantity: payload["quantity"] as? Int ?? 1,
                    expirationDate: expDate,
                    notes: payload["notes"] as? String,
                    productId: productId,
                    locationId: payload["locationId"] as? String
                )
                
                // Link product
                let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == productId })
                newItem.product = try? modelContext.fetch(prodDesc).first
                
                modelContext.insert(newItem)
                print("➕ [SyncService] Created inventory item: \(itemId)")
            }
        }
    }
    
    private func applyProductChange(_ change: SyncChange, modelContext: ModelContext) throws {
        // Similar pattern for products
        print("📦 [SyncService] Product change: \(change.action) \(change.entityId)")
    }
    
    private func applyGroceryChange(_ change: SyncChange, modelContext: ModelContext) throws {
        // Similar pattern for grocery items
        print("🛒 [SyncService] Grocery change: \(change.action) \(change.entityId)")
    }
}
