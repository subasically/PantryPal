import Foundation
import SwiftData

@MainActor
final class SyncService: Sendable {
    static let shared = SyncService()
    
    private init() {}
    
    func syncFromRemote(modelContext: ModelContext) async throws {
        // 1. Fetch all data from API
        async let fullSyncResponse = APIService.shared.fullSync()
        async let locationsResponse = APIService.shared.getLocationsHierarchy()
        
        let (syncData, locationsData) = try await (fullSyncResponse, locationsResponse)
        
        // 2. Sync Locations
        // We flatten the hierarchy for storage, but keep parentId
        let flatLocations = flattenLocations(locationsData.locations)
        
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
        
        // Delete items not in remote
        for item in allItems {
            if !remoteIds.contains(item.id) {
                modelContext.delete(item)
            }
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for item in syncData.inventory {
            let itemId = item.id
            let descriptor = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == itemId })
            let existing = try? modelContext.fetch(descriptor).first
            
            let expDate: Date? = item.expirationDate != nil ? dateFormatter.date(from: item.expirationDate!) : nil
            
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
}
