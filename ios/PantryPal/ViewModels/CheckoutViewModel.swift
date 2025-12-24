import SwiftUI
import SwiftData

@MainActor
@Observable
final class CheckoutViewModel {
    var lastCheckout: CheckoutScanResponse?
    var isProcessing = false
    var errorMessage: String?
    var history: [CheckoutHistoryItem] = []
    
    private var modelContext: ModelContext?
    
    func setContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func processCheckout(upc: String) async {
        guard let context = modelContext else { return }
        isProcessing = true
        errorMessage = nil
        lastCheckout = nil
        HapticService.shared.mediumImpact()
        
        // 1. Local Lookup
        // Find product by UPC
        let productDescriptor = FetchDescriptor<SDProduct>(predicate: #Predicate { $0.upc == upc })
        guard let product = try? context.fetch(productDescriptor).first else {
            // Product not found locally.
            // If online, we could try API, but for pure offline-first, we fail or fallback.
            // Let's try API as fallback if online, otherwise fail.
            do {
                let response = try await APIService.shared.checkoutScan(upc: upc)
                lastCheckout = response
                handleSuccess(response)
            } catch {
                errorMessage = "Product not found locally or offline: \(error.localizedDescription)"
                HapticService.shared.error()
            }
            isProcessing = false
            return
        }
        
        // Find inventory item (prefer oldest expiration)
        let productId = product.id
        let itemDescriptor = FetchDescriptor<SDInventoryItem>(
            predicate: #Predicate { $0.productId == productId },
            sortBy: [SortDescriptor(\.expirationDate)]
        )
        
        guard let item = try? context.fetch(itemDescriptor).first else {
            // Product found but no inventory
            lastCheckout = CheckoutScanResponse(
                success: false,
                message: nil,
                product: CheckoutProduct(id: product.id, name: product.name, brand: product.brand, imageUrl: product.imageUrl),
                previousQuantity: 0,
                newQuantity: 0,
                itemDeleted: false,
                inventoryItem: nil,
                checkoutId: nil,
                error: "Item not in inventory",
                found: true,
                inStock: false,
                upc: upc
            )
            isProcessing = false
            return
        }
        
        // 2. Local Update
        let previousQty = item.quantity
        let newQty = previousQty - 1
        var itemDeleted = false
        
        if newQty <= 0 {
            context.delete(item)
            itemDeleted = true
        } else {
            item.quantity = newQty
        }
        
        try? context.save()
        
        // 3. Enqueue Action
        ActionQueueService.shared.enqueue(
            context: context,
            type: .checkout,
            endpoint: "/checkout/scan",
            method: "POST",
            body: CheckoutScanRequest(upc: upc)
        )
        
        // 4. Success Response
        let response = CheckoutScanResponse(
            success: true,
            message: "Checked out 1x \(product.name)",
            product: CheckoutProduct(id: product.id, name: product.name, brand: product.brand, imageUrl: product.imageUrl),
            previousQuantity: previousQty,
            newQuantity: newQty,
            itemDeleted: itemDeleted,
            inventoryItem: itemDeleted ? nil : item.toDomain(),
            checkoutId: UUID().uuidString, // Local ID
            error: nil,
            found: true,
            inStock: true,
            upc: upc
        )
        
        lastCheckout = response
        handleSuccess(response)
        isProcessing = false
    }
    
    private func handleSuccess(_ response: CheckoutScanResponse) {
        if response.success == true {
            HapticService.shared.success()
            // Send notification logic could be here
        } else {
            HapticService.shared.warning()
        }
    }
    
    func loadHistory() async {
        // For now, load from API. Offline history is harder without syncing the history table.
        do {
            let response = try await APIService.shared.getCheckoutHistory()
            history = response.history
        } catch {
            print("Failed to load history: \(error)")
        }
    }
}
