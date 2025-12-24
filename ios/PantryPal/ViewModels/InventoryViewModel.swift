import SwiftUI

@MainActor
@Observable
final class InventoryViewModel {
    var items: [InventoryItem] = []
    var expiringItems: [InventoryItem] = []
    var expiredItems: [InventoryItem] = []
    var locations: [LocationFlat] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?
    
    func loadInventory() async {
        isLoading = true
        errorMessage = nil
        
        do {
            items = try await APIService.shared.getInventory()
            // Schedule expiration notifications for items with expiration dates
            await NotificationService.shared.scheduleExpirationNotifications(for: items)
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func loadLocations() async {
        do {
            locations = try await APIService.shared.getLocations()
        } catch {
            print("Failed to load locations: \(error)")
        }
    }
    
    func loadExpiringItems(days: Int = 7) async {
        do {
            expiringItems = try await APIService.shared.getExpiringItems(days: days)
        } catch {
            print("Failed to load expiring items: \(error)")
        }
    }
    
    func loadExpiredItems() async {
        do {
            expiredItems = try await APIService.shared.getExpiredItems()
        } catch {
            print("Failed to load expired items: \(error)")
        }
    }
    
    func quickAdd(upc: String, quantity: Int = 1, expirationDate: Date? = nil, locationId: String) async -> QuickAddResponse? {
        errorMessage = nil
        successMessage = nil
        
        var dateString: String? = nil
        if let date = expirationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dateString = formatter.string(from: date)
        }
        
        do {
            let response = try await APIService.shared.quickAdd(upc: upc, quantity: quantity, expirationDate: dateString, locationId: locationId)
            
            if response.requiresCustomProduct == true {
                return response
            }
            
            if let item = response.item {
                successMessage = response.action == "updated" 
                    ? "Updated \(item.displayName)" 
                    : "Added \(item.displayName)"
                HapticService.shared.itemAdded()
                await loadInventory()
            }
            
            return response
        } catch let error as APIError {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
            return nil
        } catch {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
            return nil
        }
    }
    
    func addItem(productId: String, quantity: Int = 1, expirationDate: Date? = nil, notes: String? = nil, locationId: String) async -> Bool {
        errorMessage = nil
        
        var dateString: String? = nil
        if let date = expirationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dateString = formatter.string(from: date)
        }
        
        do {
            let item = try await APIService.shared.addToInventory(productId: productId, quantity: quantity, expirationDate: dateString, notes: notes, locationId: locationId)
            successMessage = "Added \(item.displayName)"
            HapticService.shared.itemAdded()
            await loadInventory()
            return true
        } catch let error as APIError {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
            return false
        } catch {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
            return false
        }
    }
    
    func adjustQuantity(id: String, adjustment: Int) async {
        errorMessage = nil
        
        do {
            let response = try await APIService.shared.adjustQuantity(id: id, adjustment: adjustment)
            if response.wasDeleted {
                // Item was deleted because quantity hit 0
                items.removeAll { $0.id == id }
                successMessage = "Item removed from pantry"
                HapticService.shared.itemDeleted()
            } else if let newQuantity = response.quantity {
                // Update the item locally for instant feedback
                if let index = items.firstIndex(where: { $0.id == id }) {
                    items[index].quantity = newQuantity
                }
                HapticService.shared.itemRemoved()
            }
        } catch let error as APIError {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
        } catch {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
        }
    }
    
    func getItem(id: String) -> InventoryItem? {
        items.first { $0.id == id }
    }
    
    func deleteItem(id: String) async {
        errorMessage = nil
        
        do {
            try await APIService.shared.deleteInventoryItem(id: id)
            items.removeAll { $0.id == id }
            HapticService.shared.itemDeleted()
        } catch let error as APIError {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
        } catch {
            errorMessage = error.localizedDescription
            HapticService.shared.errorOccurred()
        }
    }
    
    func updateItem(id: String, quantity: Int?, expirationDate: Date?, notes: String?, locationId: String? = nil) async {
        errorMessage = nil
        
        var dateString: String? = nil
        if let date = expirationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            dateString = formatter.string(from: date)
        }
        
        do {
            _ = try await APIService.shared.updateInventoryItem(id: id, quantity: quantity, expirationDate: dateString, notes: notes, locationId: locationId)
            await loadInventory()
        } catch let error as APIError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func addSmartItem(name: String, upc: String?, expirationDate: Date?) async -> Bool {
        // Default location (first one)
        guard let locationId = locations.first?.id else {
            errorMessage = "No location found"
            return false
        }
        
        // 1. Try Quick Add if we have a UPC
        if let upc = upc {
            let response = await quickAdd(upc: upc, quantity: 1, expirationDate: expirationDate, locationId: locationId)
            
            // If successful and didn't require custom product, we are done
            if let response = response, response.requiresCustomProduct != true {
                return true
            }
            
            // If failed or requires custom product, proceed to create product
        }
        
        // 2. Create Product
        do {
            let product = try await APIService.shared.createProduct(
                upc: upc,
                name: name,
                brand: nil,
                description: "Added via Smart Scanner",
                category: "Uncategorized"
            )
            
            // 3. Add to Inventory
            return await addItem(
                productId: product.id,
                quantity: 1,
                expirationDate: expirationDate,
                notes: "Added via Smart Scanner",
                locationId: locationId
            )
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
