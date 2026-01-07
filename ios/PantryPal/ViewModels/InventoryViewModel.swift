import SwiftUI
import SwiftData

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
    
    private var modelContext: ModelContext?
    var currentHousehold: Household?
    
    func setContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func loadInventory(withLoadingState: Bool = true) async {
        guard let context = modelContext else { return }
        if withLoadingState { isLoading = true }
        errorMessage = nil
        
        // Load from local database
        do {
            let descriptor = FetchDescriptor<SDInventoryItem>(sortBy: [SortDescriptor(\SDInventoryItem.product?.name)])
            let sdItems = try context.fetch(descriptor)
            
            // Convert to domain model
            self.items = sdItems.map { $0.toDomain() }
            
            // Schedule notifications (Premium only, handled in NotificationService)
            NotificationService.shared.currentHousehold = currentHousehold
            await NotificationService.shared.scheduleExpirationNotifications(for: items)
        } catch {
            errorMessage = "Failed to load local inventory: \(error.userFriendlyMessage)"
        }
        
        if withLoadingState { isLoading = false }
    }
    
    func loadLocations() async {
        guard let context = modelContext else { return }
        
        do {
            let descriptor = FetchDescriptor<SDLocation>(sortBy: [SortDescriptor(\.sortOrder)])
            let sdLocations = try context.fetch(descriptor)
            self.locations = sdLocations.map { $0.toFlat() }
        } catch {
            print("Failed to load local locations: \(error)")
        }
    }
    
    // ... (keep expiring/expired loaders if needed, or derive from items)
    
    func addCustomItem(product: Product, quantity: Int, expirationDate: Date?, locationId: String) async -> Bool {
        guard let context = modelContext else { return false }
        
        // 1. Ensure Product exists locally
        let productId = product.id
        let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate<SDProduct> { $0.id == productId })
        if (try? context.fetch(prodDesc).first) == nil {
            let newProd = SDProduct(
                id: product.id,
                upc: product.upc,
                name: product.name,
                brand: product.brand,
                details: product.description,
                imageUrl: product.imageUrl,
                category: product.category,
                isCustom: true,
                householdId: "current"
            )
            context.insert(newProd)
            try? context.save() // Save to ensure it's available for addItem
        }
        
        // 2. Call addItem
        return await addItem(productId: productId, quantity: quantity, expirationDate: expirationDate, locationId: locationId)
    }
    
    func addItem(productId: String, quantity: Int = 1, expirationDate: Date? = nil, notes: String? = nil, locationId: String) async -> Bool {
        guard let context = modelContext else { return false }
        errorMessage = nil
        
        // 1. Create local item immediately
        let newItemId = UUID().uuidString // Generate temporary ID
        let newItem = SDInventoryItem(
            id: newItemId,
            householdId: "current", // Placeholder, will be overwritten by sync
            quantity: quantity,
            expirationDate: expirationDate,
            notes: notes,
            productId: productId,
            locationId: locationId
        )
        
        // Link relationships
        let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == productId })
        newItem.product = try? context.fetch(prodDesc).first
        
        let locDesc = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == locationId })
        newItem.location = try? context.fetch(locDesc).first
        
        context.insert(newItem)
        
        // 2. Enqueue action
        let dateString: String? = expirationDate.map { 
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: $0) 
        }
        
        struct AddRequest: Codable {
            let productId: String
            let quantity: Int
            let expirationDate: String?
            let notes: String?
            let locationId: String
            // We send the temp ID so server can map it if we want, but for now server generates ID.
            // Ideally, we should let client generate ID.
        }
        
        let body = AddRequest(productId: productId, quantity: quantity, expirationDate: dateString, notes: notes, locationId: locationId)
        
        ActionQueueService.shared.enqueue(
            context: context,
            type: .create,
            endpoint: "/inventory",
            method: "POST",
            body: body
        )
        
        // 3. Process queue immediately to upload the new item
        await ActionQueueService.shared.processQueue(modelContext: context)
        
        successMessage = "Added \(newItem.product?.name ?? "item")"
        HapticService.shared.itemAdded()
        await loadInventory()
        return true
    }
    
    func updateItem(id: String, quantity: Int?, expirationDate: Date?, notes: String?, locationId: String? = nil) async {
        print("📝 [InventoryViewModel] updateItem called for ID: \(id)")
        print("   - Quantity: \(quantity?.description ?? "nil")")
        print("   - Expiration date: \(expirationDate?.description ?? "nil (clearing expiration)")")
        print("   - Notes: \(notes ?? "nil")")
        print("   - Location ID: \(locationId ?? "nil")")
        
        guard let context = modelContext else {
            print("❌ [InventoryViewModel] modelContext is nil")
            return
        }
        errorMessage = nil
        
        // 1. Update local item
        let descriptor = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? context.fetch(descriptor).first else {
            print("❌ [InventoryViewModel] Item not found in SwiftData: \(id)")
            return
        }
        
        print("📦 [InventoryViewModel] Current item state:")
        print("   - Current quantity: \(item.quantity)")
        print("   - Current expiration: \(item.expirationDate?.description ?? "nil")")
        print("   - Current notes: \(item.notes ?? "nil")")
        print("   - Current location: \(String(describing: item.locationId))")
        
        if let q = quantity { 
            print("   ✏️ Updating quantity: \(item.quantity) → \(q)")
            item.quantity = q 
        }
        
        // CRITICAL: Handle explicit nil to clear expiration
        if expirationDate == nil {
            print("   🗑️ Clearing expiration date (was: \(item.expirationDate.map(String.init(describing:)) ?? "nil"))")
            item.expirationDate = nil
        } else if let e = expirationDate {
            print("   📅 Setting expiration date: \(e)")
            item.expirationDate = e
        }
        
        if let n = notes { 
            print("   📝 Updating notes: \(item.notes ?? "nil") → \(n)")
            item.notes = n 
        }
        if let l = locationId { 
            print("   📍 Updating location: \(String(describing: item.locationId)) → \(l)")
            item.locationId = l
            let locDesc = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == l })
            item.location = try? context.fetch(locDesc).first
        }
        
        do {
            try context.save()
            print("✅ [InventoryViewModel] SwiftData saved successfully")
        } catch {
            print("❌ [InventoryViewModel] Failed to save SwiftData: \(error)")
        }
        
        // 2. Enqueue action
        let dateString: String? = expirationDate.map { 
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: $0) 
        }
        
        print("📤 [InventoryViewModel] Preparing API request:")
        print("   - Expiration date string: \(dateString ?? "nil")")
        
        struct UpdateRequest: Codable {
            let quantity: Int?
            let expirationDate: String?
            let notes: String?
            let locationId: String?
        }
        
        let body = UpdateRequest(quantity: quantity, expirationDate: dateString, notes: notes, locationId: locationId)
        
        print("📋 [InventoryViewModel] Request body: quantity=\(quantity?.description ?? "nil"), expiration=\(dateString ?? "nil"), notes=\(notes ?? "nil"), location=\(locationId ?? "nil")")
        
        ActionQueueService.shared.enqueue(
            context: context,
            type: .update,
            endpoint: "/inventory/\(id)",
            method: "PUT",
            body: body
        )
        
        print("✅ [InventoryViewModel] Action enqueued, processing queue...")
        
        // 3. Process queue immediately
        await ActionQueueService.shared.processQueue(modelContext: context)
        
        print("✅ [InventoryViewModel] Queue processed, reloading inventory...")
        await loadInventory()
        print("✅ [InventoryViewModel] updateItem completed")
    }
    
    func deleteItem(id: String) async {
        guard let context = modelContext else { return }
        errorMessage = nil
        
        // 1. Delete local
        let descriptor = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == id })
        if let item = try? context.fetch(descriptor).first {
            context.delete(item)
            try? context.save()
        }
        
        // 2. Enqueue action
        ActionQueueService.shared.enqueue(
            context: context,
            type: .delete,
            endpoint: "/inventory/\(id)",
            method: "DELETE"
        )
        
        // 3. Process queue immediately
        await ActionQueueService.shared.processQueue(modelContext: context)
        
        items.removeAll { $0.id == id }
        HapticService.shared.itemDeleted()
    }
    
    func adjustQuantity(id: String, adjustment: Int) async {
        guard let context = modelContext else { return }
        
        // 1. Local update
        let descriptor = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == id })
        guard let item = try? context.fetch(descriptor).first else { return }
        
        let newQuantity = item.quantity + adjustment
        
        if newQuantity <= 0 {
            context.delete(item)
            items.removeAll { $0.id == id }
            successMessage = "Item removed"
            HapticService.shared.itemDeleted()
        } else {
            item.quantity = newQuantity
            if let index = items.firstIndex(where: { $0.id == id }) {
                items[index].quantity = newQuantity
            }
            HapticService.shared.itemRemoved()
        }
        try? context.save()
        
        // 2. Enqueue action
        struct QuantityAdjustRequest: Codable {
            let adjustment: Int
        }
        
        ActionQueueService.shared.enqueue(
            context: context,
            type: .update,
            endpoint: "/inventory/\(id)/quantity",
            method: "PATCH",
            body: QuantityAdjustRequest(adjustment: adjustment)
        )
        
        // 3. Process queue immediately
        await ActionQueueService.shared.processQueue(modelContext: context)
    }

    // ... (keep other methods, adapting them similarly)

    
    func quickAdd(upc: String, quantity: Int = 1, expirationDate: Date? = nil, locationId: String) async -> QuickAddResponse? {
        // For quick add, we might still want to hit the API to check for product existence/custom product requirement
        // Or we can implement local lookup.
        // For now, let's keep it hybrid: Check API, if success, update local.
        
        let dateString: String? = expirationDate.map { 
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: $0) 
        }
        
        do {
            let response = try await APIService.shared.quickAdd(upc: upc, quantity: quantity, expirationDate: dateString, locationId: locationId)
            
            // Update local database immediately with the result
            if let item = response.item, let context = modelContext {
                print("✅ [InventoryViewModel] Quick add success, updating local DB for item: \(item.id)")
                
                // 1. Ensure Product exists
                let productId = item.productId
                let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == productId })
                if (try? context.fetch(prodDesc).first) == nil {
                    let newProd = SDProduct(
                        id: productId,
                        upc: item.productUpc,
                        name: item.productName ?? "Unknown",
                        brand: item.productBrand,
                        details: nil,
                        imageUrl: item.productImageUrl,
                        category: item.productCategory,
                        isCustom: false,
                        householdId: item.householdId
                    )
                    context.insert(newProd)
                }
                
                // 2. Update/Insert Inventory Item
                let itemId = item.id
                let itemDesc = FetchDescriptor<SDInventoryItem>(predicate: #Predicate { $0.id == itemId })
                
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let expDate = item.expirationDate.flatMap { dateFormatter.date(from: $0) }
                
                if let existing = try? context.fetch(itemDesc).first {
                    existing.quantity = item.quantity
                    existing.expirationDate = expDate
                    existing.notes = item.notes
                    existing.locationId = item.locationId
                    
                    // Link Product
                    let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == productId })
                    existing.product = try? context.fetch(prodDesc).first
                    
                    // Link Location
                    if let locId = item.locationId {
                        let locDesc = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == locId })
                        existing.location = try? context.fetch(locDesc).first
                    }
                } else {
                    let newItem = SDInventoryItem(
                        id: itemId,
                        householdId: item.householdId,
                        quantity: item.quantity,
                        expirationDate: expDate,
                        notes: item.notes,
                        productId: productId,
                        locationId: item.locationId
                    )
                    
                    // Link Product
                    let prodDesc = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.id == productId })
                    newItem.product = try? context.fetch(prodDesc).first
                    
                    // Link Location
                    if let locId = item.locationId {
                        let locDesc = FetchDescriptor<SDLocation>(predicate: #Predicate { $0.id == locId })
                        newItem.location = try? context.fetch(locDesc).first
                    }
                    
                    context.insert(newItem)
                }
                
                try? context.save()
                await loadInventory()
            }
            
            return response
        } catch {
            errorMessage = error.userFriendlyMessage
            return nil
        }
    }
    
    func addSmartItem(name: String, upc: String?, expirationDate: Date?) async -> Bool {
        guard let context = modelContext else { return false }
        guard let locationId = locations.first?.id else {
            errorMessage = "No location found"
            return false
        }
        
        // 1. Create/Find Product Locally
        var productId: String?
        
        // Check if product exists locally by UPC
        if let upc = upc {
            let descriptor = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.upc == upc })
            if let existing = try? context.fetch(descriptor).first {
                productId = existing.id
            }
        }
        
        if productId == nil {
            // Create new local product
            let newProductId = UUID().uuidString
            let newProduct = SDProduct(
                id: newProductId,
                upc: upc,
                name: name,
                brand: nil,
                details: "Added via Smart Scanner",
                imageUrl: nil,
                category: "Uncategorized",
                isCustom: true,
                householdId: "current"
            )
            context.insert(newProduct)
            productId = newProductId
            
            // Enqueue Product Creation
            struct CreateProductRequest: Codable {
                let upc: String?
                let name: String
                let brand: String?
                let description: String?
                let category: String?
            }
            
            ActionQueueService.shared.enqueue(
                context: context,
                type: .create,
                endpoint: "/products",
                method: "POST",
                body: CreateProductRequest(upc: upc, name: name, brand: nil, description: "Added via Smart Scanner", category: "Uncategorized")
            )
        }
        
        // 2. Add Item
        if let pid = productId {
            return await addItem(productId: pid, quantity: 1, expirationDate: expirationDate, locationId: locationId)
        }
        
        return false
    }
    
    // Helper to load expiring/expired from local
    func loadExpiringItems(days: Int = 7) async {
        // Filter local items
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let today = Calendar.current.startOfDay(for: Date())
        let threshold = Calendar.current.date(byAdding: .day, value: days, to: today)!
        
        expiringItems = items.filter { 
            guard let dateStr = $0.expirationDate,
                  let date = dateFormatter.date(from: dateStr) else { return false }
            
            let itemDate = Calendar.current.startOfDay(for: date)
            return itemDate >= today && itemDate <= threshold
        }
    }
    
    func loadExpiredItems() async {
        expiredItems = items.filter { $0.isExpired }
    }
    
    func getItem(id: String) -> InventoryItem? {
        items.first { $0.id == id }
    }
}
