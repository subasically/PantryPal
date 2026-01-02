import StoreKit
import Foundation

enum StoreError: LocalizedError {
    case failedVerification
    case pending
    case unknown
    case purchaseFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed"
        case .pending:
            return "Purchase is pending approval"
        case .unknown:
            return "An unknown error occurred"
        case .purchaseFailed(let error):
            return "Purchase failed: \(error.localizedDescription)"
        }
    }
}

/// Manages StoreKit 2 in-app purchases for Premium subscriptions
@MainActor
final class StoreKitService: ObservableObject {
    static let shared = StoreKitService()
    
    // Products
    @Published var monthlyProduct: Product?
    @Published var annualProduct: Product?
    @Published var isLoading = false
    @Published var purchaseInProgress = false
    
    // Product IDs (will be configured in App Store Connect)
    private let monthlyProductID = "com.pantrypal.premium.monthly"
    private let annualProductID = "com.pantrypal.premium.annual"
    
    // Transaction listener
    private var updateListenerTask: Task<Void, Error>?
    
    private init() {
        updateListenerTask = listenForTransactions()
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Product Loading
    
    /// Load available subscription products from App Store
    func loadProducts() async throws {
        print("🛒 [StoreKit] Loading products...")
        isLoading = true
        defer { isLoading = false }
        
        do {
            let products = try await Product.products(for: [monthlyProductID, annualProductID])
            
            for product in products {
                switch product.id {
                case monthlyProductID:
                    monthlyProduct = product
                    print("✅ [StoreKit] Loaded monthly: \(product.displayPrice)")
                case annualProductID:
                    annualProduct = product
                    print("✅ [StoreKit] Loaded annual: \(product.displayPrice)")
                default:
                    print("⚠️ [StoreKit] Unknown product: \(product.id)")
                }
            }
            
            if monthlyProduct == nil && annualProduct == nil {
                print("❌ [StoreKit] No products loaded. Check App Store Connect configuration.")
            }
        } catch {
            print("❌ [StoreKit] Failed to load products: \(error)")
            throw error
        }
    }
    
    // MARK: - Purchase Flow
    
    /// Purchase a subscription product
    /// - Parameter product: The subscription product to purchase
    /// - Returns: The verified transaction if successful, nil if cancelled
    func purchase(_ product: Product) async throws -> Transaction? {
        guard !purchaseInProgress else {
            print("⚠️ [StoreKit] Purchase already in progress")
            return nil
        }
        
        print("🛒 [StoreKit] Starting purchase: \(product.id)")
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                print("✅ [StoreKit] Purchase successful: \(transaction.id)")
                
                // Sync with server
                await verifyAndSync(transaction)
                
                // Finish the transaction
                await transaction.finish()
                
                return transaction
                
            case .userCancelled:
                print("ℹ️ [StoreKit] User cancelled purchase")
                return nil
                
            case .pending:
                print("⏳ [StoreKit] Purchase pending approval")
                throw StoreError.pending
                
            @unknown default:
                print("❌ [StoreKit] Unknown purchase result")
                throw StoreError.unknown
            }
        } catch {
            print("❌ [StoreKit] Purchase failed: \(error)")
            throw StoreError.purchaseFailed(error)
        }
    }
    
    // MARK: - Restore Purchases
    
    /// Restore previous purchases
    func restorePurchases() async throws {
        print("🔄 [StoreKit] Restoring purchases...")
        
        var restoredCount = 0
        
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                // Only process active subscriptions
                if let expirationDate = transaction.expirationDate,
                   expirationDate > Date() {
                    await verifyAndSync(transaction)
                    restoredCount += 1
                }
            } catch {
                print("❌ [StoreKit] Failed to verify transaction during restore: \(error)")
            }
        }
        
        print("✅ [StoreKit] Restored \(restoredCount) purchases")
        
        if restoredCount == 0 {
            // No active subscriptions found - this is not an error
            print("ℹ️ [StoreKit] No active subscriptions to restore")
        }
    }
    
    // MARK: - Transaction Listener
    
    /// Listen for transaction updates (renewals, expirations, etc.)
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            print("👂 [StoreKit] Listening for transaction updates...")
            
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    print("🔔 [StoreKit] Transaction update received: \(transaction.id)")
                    
                    await self.verifyAndSync(transaction)
                    await transaction.finish()
                } catch {
                    print("❌ [StoreKit] Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Verification
    
    /// Verify the transaction cryptographic signature
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            print("❌ [StoreKit] Transaction failed verification")
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    /// Verify transaction with backend and update Premium status
    private func verifyAndSync(_ transaction: Transaction) async {
        print("🔐 [StoreKit] Verifying transaction with server: \(transaction.id)")
        
        do {
            // Build validation request
            let validationData: [String: Any] = [
                "transactionId": String(transaction.id),
                "productId": transaction.productID,
                "originalTransactionId": String(transaction.originalID),
                "expiresAt": transaction.expirationDate?.ISO8601Format() ?? ""
            ]
            
            // Send to server for validation
            let response = try await APIService.shared.validateReceipt(validationData)
            
            print("✅ [StoreKit] Server validated subscription. Premium expires: \(response.household.premiumExpiresAt ?? "N/A")")
            
            // The server response will trigger a sync that updates local Premium status
            // No need to manually update here - let the sync system handle it
            
        } catch {
            print("❌ [StoreKit] Failed to verify with server: \(error)")
            // Don't throw - we don't want to block the purchase flow
            // The transaction listener will retry on next app launch
        }
    }
    
    // MARK: - Subscription Status
    
    /// Check if user has an active subscription
    func hasActiveSubscription() async -> Bool {
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               let expirationDate = transaction.expirationDate,
               expirationDate > Date() {
                return true
            }
        }
        return false
    }
}
