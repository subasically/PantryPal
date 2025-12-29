import Foundation
import Observation

@MainActor
@Observable
final class GroceryViewModel {
    var items: [GroceryItem] = []
    var isLoading = false
    var errorMessage: String?
    
    func fetchItems() async {
        isLoading = true
        errorMessage = nil
        
        do {
            items = try await APIService.shared.fetchGroceryItems()
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
            return true
        } catch {
            if let apiError = error as? APIError,
               case .serverError(let message) = apiError {
                if message.contains("already on grocery list") {
                    errorMessage = "Already on your list"
                } else if message.contains("household") {
                    errorMessage = "Please create or join a household first"
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
        
        do {
            try await APIService.shared.removeGroceryItem(id: item.id)
        } catch {
            // Revert on error
            if let index = index {
                items.insert(item, at: index)
            }
            errorMessage = "Failed to remove item"
            print("Remove grocery error: \(error)")
        }
    }
}
