import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class GroceryViewModel {
    var items: [GroceryItem] = []
    var isLoading = false
    var errorMessage: String?
    
    private var modelContext: ModelContext?
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
        loadFromCache()
    }
    
    // Load from local cache (SwiftData)
    private func loadFromCache() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<SDGroceryItem>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        if let cached = try? context.fetch(descriptor) {
            items = cached.map { $0.toGroceryItem() }
        }
    }
    
    func fetchItems() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let remoteItems = try await APIService.shared.fetchGroceryItems()
            items = remoteItems
            
            // Update local cache
            if let context = modelContext {
                // Clear old items
                let descriptor = FetchDescriptor<SDGroceryItem>()
                if let existing = try? context.fetch(descriptor) {
                    existing.forEach { context.delete($0) }
                }
                
                // Insert new items
                remoteItems.forEach { item in
                    let sdItem = SDGroceryItem(
                        id: item.id,
                        householdId: item.householdId,
                        name: item.name,
                        brand: item.brand,
                        upc: item.upc,
                        normalizedName: item.normalizedName,
                        createdAt: ISO8601DateFormatter().date(from: item.createdAt ?? "") ?? Date()
                    )
                    context.insert(sdItem)
                }
                
                try? context.save()
            }
        } catch {
            errorMessage = "Failed to load grocery list"
            print("Fetch grocery error: \(error)")
        }
        
        isLoading = false
    }
    
    func addItem(name: String) async -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        
        errorMessage = nil
        
        do {
            let newItem = try await APIService.shared.addGroceryItem(name: name)
            items.insert(newItem, at: 0) // Add to top
            
            // Update local cache
            if let context = modelContext {
                let sdItem = SDGroceryItem(
                    id: newItem.id,
                    householdId: newItem.householdId,
                    name: newItem.name,
                    brand: newItem.brand,
                    upc: newItem.upc,
                    normalizedName: newItem.normalizedName,
                    createdAt: ISO8601DateFormatter().date(from: newItem.createdAt ?? "") ?? Date()
                )
                context.insert(sdItem)
                try? context.save()
            }
            
            return true
        } catch {
            if let apiError = error as? APIError,
               case .serverError(let message) = apiError {
                if message.contains("already on grocery list") {
                    errorMessage = "Already on your list"
                } else if message.contains("household") {
                    errorMessage = "Please create or join a household first"
                } else if message.contains("limit reached") {
                    errorMessage = "Grocery list limit reached. Upgrade to Premium for unlimited items."
                } else {
                    errorMessage = message
                }
            } else {
                errorMessage = "Failed to add item: \(error.localizedDescription)"
            }
            print("Add grocery error: \(error)")
            return false
        }
    }
    
    func removeItem(_ item: GroceryItem) async {
        // Optimistic update
        let index = items.firstIndex(where: { $0.id == item.id })
        if let index = index {
            items.remove(at: index)
        }
        
        // Remove from cache
        if let context = modelContext {
            let descriptor = FetchDescriptor<SDGroceryItem>(predicate: #Predicate { $0.id == item.id })
            if let sdItem = try? context.fetch(descriptor).first {
                context.delete(sdItem)
                try? context.save()
            }
        }
        
        do {
            try await APIService.shared.removeGroceryItem(id: item.id)
        } catch {
            // Revert on error
            if let index = index {
                items.insert(item, at: index)
                
                // Re-add to cache
                if let context = modelContext {
                    let sdItem = SDGroceryItem(
                        id: item.id,
                        householdId: item.householdId,
                        name: item.name,
                        brand: item.brand,
                        upc: item.upc,
                        normalizedName: item.normalizedName,
                        createdAt: ISO8601DateFormatter().date(from: item.createdAt ?? "") ?? Date()
                    )
                    context.insert(sdItem)
                    try? context.save()
                }
            }
            errorMessage = "Failed to remove item"
            print("Remove grocery error: \(error)")
        }
    }
    
    // MARK: - Auto-Remove on Restock
    
    /// Attempts to remove a grocery item when inventory is restocked
    /// - Parameters:
    ///   - upc: UPC code if available (preferred matching)
    ///   - name: Product name for fallback matching
    ///   - brand: Product brand for fallback matching
    /// - Returns: True if an item was removed
    @discardableResult
    func attemptAutoRemove(upc: String?, name: String, brand: String?) async -> Bool {
        print("🛒 [AutoRemove] Called - UPC: \(upc ?? "nil"), Name: \(name), Brand: \(brand ?? "nil")")
        
        do {
            var removed = false
            
            // Priority 1: Try UPC match if available
            if let upc = upc, !upc.isEmpty {
                print("🛒 [AutoRemove] Attempting UPC match...")
                removed = try await APIService.shared.removeGroceryItemByUPC(upc: upc)
                if removed {
                    print("🛒 [AutoRemove] ✅ Removed by UPC")
                    await fetchItems() // Refresh list
                    return true
                }
                print("🛒 [AutoRemove] No match by UPC")
            }
            
            // Priority 2: Fallback to name match
            let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            
            print("🛒 [AutoRemove] Attempting name match with: \(normalizedName)")
            removed = try await APIService.shared.removeGroceryItemByName(normalizedName: normalizedName)
            
            if removed {
                print("🛒 [AutoRemove] ✅ Removed by name")
                await fetchItems() // Refresh list
                return true
            }
            
            print("🛒 [AutoRemove] No match found")
            return false
        } catch {
            print("🛒 [AutoRemove] ❌ Error: \(error)")
            return false
        }
    }
}
