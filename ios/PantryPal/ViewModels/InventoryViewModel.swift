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
}
