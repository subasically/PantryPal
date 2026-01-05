import StoreKit
import Foundation
import StoreKit

enum StoreError: LocalizedError {
    case failedVerification
    case pending
    case unknown
    case interrupted
    case purchaseFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .failedVerification:
            return "Transaction verification failed. Please try again."
        case .pending:
            return "Purchase is pending approval. Check back later."
        case .interrupted:
            return "Purchase was interrupted. Please try again."
        case .unknown:
            return "An unknown error occurred. Please try again."
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
    @Published var monthlyProduct: StoreKit.Product?
    @Published var annualProduct: StoreKit.Product?
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
            let productIDs: Set<String> = [monthlyProductID, annualProductID]
            let products = try await StoreKit.Product.products(for: productIDs)
            
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
    /// - Returns: A tuple with the verified transaction (if successful, nil if cancelled) and updated household (if available)
    func purchase(_ product: StoreKit.Product) async throws -> (StoreKit.Transaction?, Household?) {
        guard !purchaseInProgress else {
            print("⚠️ [StoreKit] Purchase already in progress")
            return (nil, nil)
        }
        
        print("🛒 [StoreKit] Starting purchase: \(product.id)")
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Verify the transaction
                let transaction: StoreKit.Transaction
                do {
                    transaction = try checkVerified(verification)
                    print("✅ [StoreKit] Purchase successful: \(transaction.id)")
                } catch {
                    print("❌ [StoreKit] Transaction verification failed: \(error)")
                    throw StoreError.failedVerification
                }
                
                // Sync with server and get updated household
                let updatedHousehold = await verifyAndSync(transaction)
                
                // Finish the transaction
                await transaction.finish()
                
                return (transaction, updatedHousehold)
                
            case .userCancelled:
                print("ℹ️ [StoreKit] User cancelled purchase")
                return (nil, nil)
                
            case .pending:
                print("⏳ [StoreKit] Purchase pending approval")
                throw StoreError.pending
                
            @unknown default:
                print("❌ [StoreKit] Unknown purchase result")
                throw StoreError.unknown
            }
        } catch let error as StoreError {
            // Re-throw our custom errors
            throw error
        } catch {
            // Catch interrupted purchases or other StoreKit errors
            print("❌ [StoreKit] Purchase failed: \(error)")
            
            // Check if it's an interrupted purchase (SKError.paymentCancelled = 2)
            if (error as NSError).domain == "SKErrorDomain" && (error as NSError).code == 2 {
                print("🔄 [StoreKit] Purchase was interrupted")
                throw StoreError.interrupted
            }
            
            throw StoreError.purchaseFailed(error)
        }
    }
    
    // MARK: - Restore Purchases
    
    /// Restore previous purchases
    func restorePurchases() async throws {
        print("🔄 [StoreKit] Restoring purchases...")
        
        var restoredCount = 0
        
        for await result in StoreKit.Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                
                // Only process active subscriptions
                if let expirationDate = transaction.expirationDate,
                   expirationDate > Date() {
                    _ = await verifyAndSync(transaction) // Ignore household in restore flow
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
            
            for await result in StoreKit.Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    print("🔔 [StoreKit] Transaction update received: \(transaction.id)")
                    
                    _ = await self.verifyAndSync(transaction) // Ignore household in background updates
                    await transaction.finish()
                } catch {
                    print("❌ [StoreKit] Transaction verification failed: \(error)")
                }
            }
        }
    }
    
    // MARK: - Verification
    
    /// Verify the transaction cryptographic signature
    nonisolated private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            print("❌ [StoreKit] Transaction failed verification")
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    
    /// Verify transaction with backend and update Premium status
    private func verifyAndSync(_ transaction: StoreKit.Transaction) async -> Household? {
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
            
            // Return the updated household so caller can update local state immediately
            return response.household
            
        } catch {
            print("❌ [StoreKit] Failed to verify with server: \(error)")
            // Don't throw - we don't want to block the purchase flow
            // The transaction listener will retry on next app launch
            return nil
        }
    }
    
    // MARK: - Subscription Status
    
    /// Check if user has an active subscription
    func hasActiveSubscription() async -> Bool {
        for await result in StoreKit.Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result),
               let expirationDate = transaction.expirationDate,
               expirationDate > Date() {
                return true
            }
        }
        return false
    }
}
