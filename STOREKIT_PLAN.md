# StoreKit 2 Integration Plan

**Status:** 🔜 Next Priority (Week 2)  
**Dependencies:** ✅ Premium lifecycle infrastructure complete  
**Timeline:** ~2-3 days (8-12 hours of work)

---

## 🎯 Goal

Enable users to purchase Premium subscriptions directly in the iOS app, with server-side receipt validation and automatic Premium status updates.

---

## 📋 Prerequisites (Already Complete)

✅ Server supports `premium_expires_at` column  
✅ `premiumHelper.js` utility for Premium logic  
✅ Admin endpoint for testing Premium simulation  
✅ iOS `Household` model includes `premiumExpiresAt`  
✅ Paywall UI exists and is functional  
✅ Premium features gated and tested

---

## 🛠️ Implementation Checklist

### Phase 1: App Store Connect Setup (30 mins)
- [ ] Create subscription group in App Store Connect
  - Group name: "PantryPal Premium"
  - Reference name: "premium_subscription_group"
- [ ] Add subscription products:
  - **Monthly:** `com.pantrypal.premium.monthly` - $4.99/month
  - **Annual:** `com.pantrypal.premium.annual` - $49.99/year
- [ ] Configure subscription settings:
  - [ ] Localized descriptions and screenshots
  - [ ] Free trial: 7 days (optional, decide based on strategy)
  - [ ] Grace period: 16 days (default)
  - [ ] Subscription benefits: "Unlimited items, household sharing, auto-grocery"
- [ ] Add to TestFlight for internal testing

### Phase 2: iOS StoreKit Service (2-3 hours)
- [ ] Create `StoreKitService.swift`
  ```swift
  import StoreKit
  
  @MainActor
  final class StoreKitService: ObservableObject {
      static let shared = StoreKitService()
      
      // Products
      @Published var monthlyProduct: Product?
      @Published var annualProduct: Product?
      @Published var isLoading = false
      
      // Transaction listener
      private var updateListenerTask: Task<Void, Error>?
      
      // Product IDs
      private let monthlyProductID = "com.pantrypal.premium.monthly"
      private let annualProductID = "com.pantrypal.premium.annual"
      
      init() {
          updateListenerTask = listenForTransactions()
      }
      
      deinit {
          updateListenerTask?.cancel()
      }
      
      // Load products from App Store
      func loadProducts() async throws
      
      // Purchase a product
      func purchase(_ product: Product) async throws -> Transaction?
      
      // Restore purchases
      func restorePurchases() async throws
      
      // Listen for transaction updates
      func listenForTransactions() -> Task<Void, Error>
      
      // Verify transaction and update server
      func verifyAndSync(_ transaction: Transaction) async throws
  }
  ```

- [ ] Implement product loading:
  ```swift
  func loadProducts() async throws {
      isLoading = true
      defer { isLoading = false }
      
      let products = try await Product.products(for: [monthlyProductID, annualProductID])
      
      for product in products {
          switch product.id {
          case monthlyProductID:
              monthlyProduct = product
          case annualProductID:
              annualProduct = product
          default:
              break
          }
      }
  }
  ```

- [ ] Implement purchase flow:
  ```swift
  func purchase(_ product: Product) async throws -> Transaction? {
      let result = try await product.purchase()
      
      switch result {
      case .success(let verification):
          let transaction = try checkVerified(verification)
          await verifyAndSync(transaction)
          await transaction.finish()
          return transaction
          
      case .userCancelled:
          return nil
          
      case .pending:
          throw StoreError.pending
          
      @unknown default:
          throw StoreError.unknown
      }
  }
  ```

- [ ] Implement transaction listener:
  ```swift
  func listenForTransactions() -> Task<Void, Error> {
      return Task.detached {
          for await result in Transaction.updates {
              do {
                  let transaction = try self.checkVerified(result)
                  await self.verifyAndSync(transaction)
                  await transaction.finish()
              } catch {
                  print("Transaction verification failed: \(error)")
              }
          }
      }
  }
  ```

- [ ] Add verification helper:
  ```swift
  func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
      switch result {
      case .unverified:
          throw StoreError.failedVerification
      case .verified(let safe):
          return safe
      }
  }
  ```

### Phase 3: Server Receipt Validation (2-3 hours)
- [ ] Create `server/src/routes/subscriptions.js`
- [ ] Add receipt validation endpoint:
  ```javascript
  POST /api/subscriptions/validate
  
  Request Body:
  {
    "transactionId": "2000000123456789",
    "productId": "com.pantrypal.premium.monthly",
    "originalTransactionId": "2000000123456789",
    "expiresAt": "2025-12-31T23:59:59Z"
  }
  
  Response:
  {
    "success": true,
    "household": {
      "id": "household-id",
      "isPremium": true,
      "premiumExpiresAt": "2025-12-31T23:59:59Z"
    }
  }
  ```

- [ ] Implement validation logic:
  ```javascript
  // Verify with Apple's servers (production + sandbox)
  async function verifyReceipt(transactionId) {
      // Option 1: App Store Server API (recommended)
      // - More secure
      // - Real-time subscription status
      // - Requires JWT tokens
      
      // Option 2: Receipt validation endpoint (simpler)
      // - Good for MVP
      // - Client sends transaction details
      // - Server trusts client (less secure but faster)
      
      // For MVP: Trust client, validate format only
      // Post-MVP: Integrate App Store Server API
  }
  
  // Update household Premium status
  function updateHouseholdPremium(householdId, expiresAt) {
      const db = getDb();
      db.prepare(`
          UPDATE households 
          SET is_premium = 1, premium_expires_at = ?
          WHERE id = ?
      `).run(expiresAt, householdId);
  }
  ```

- [ ] Add subscription webhook (for renewals/cancellations):
  ```javascript
  POST /api/subscriptions/webhook
  
  // Apple sends subscription status updates
  // Parse notification type:
  // - DID_RENEW → Extend premium_expires_at
  // - DID_FAIL_TO_RENEW → Keep current expiration (grace period)
  // - DID_CHANGE_RENEWAL_STATUS → User canceled (keep until expiration)
  // - EXPIRED → Already handled by premiumHelper.js
  ```

### Phase 4: Update Paywall UI (1-2 hours)
- [ ] Update `PaywallView.swift` to show products:
  ```swift
  struct PaywallView: View {
      @StateObject private var storeKit = StoreKitService.shared
      @EnvironmentObject var authVM: AuthViewModel
      @Environment(\.dismiss) var dismiss
      
      @State private var isPurchasing = false
      @State private var selectedProduct: Product?
      
      var body: some View {
          VStack {
              // Header
              Text("Upgrade to Premium")
                  .font(.largeTitle)
                  .bold()
              
              // Benefits
              VStack(alignment: .leading, spacing: 12) {
                  BenefitRow(icon: "infinity", text: "Unlimited inventory items")
                  BenefitRow(icon: "person.3", text: "Household sharing")
                  BenefitRow(icon: "cart.badge.plus", text: "Auto-add to grocery list")
              }
              
              // Products
              if let monthly = storeKit.monthlyProduct,
                 let annual = storeKit.annualProduct {
                  
                  ProductCard(product: annual, isSelected: selectedProduct == annual)
                      .onTapGesture { selectedProduct = annual }
                  
                  ProductCard(product: monthly, isSelected: selectedProduct == monthly)
                      .onTapGesture { selectedProduct = monthly }
              } else {
                  ProgressView()
              }
              
              // Purchase Button
              Button {
                  Task { await purchase() }
              } label: {
                  Text("Continue")
                      .frame(maxWidth: .infinity)
                      .padding()
                      .background(Color.primaryPurple)
                      .foregroundColor(.white)
                      .cornerRadius(12)
              }
              .disabled(selectedProduct == nil || isPurchasing)
              
              // Restore Purchases
              Button("Restore Purchases") {
                  Task { await restore() }
              }
              .foregroundColor(.secondary)
              
              // Terms & Privacy
              Text("Terms • Privacy")
                  .font(.caption)
                  .foregroundColor(.secondary)
          }
          .padding()
          .task {
              try? await storeKit.loadProducts()
          }
      }
      
      func purchase() async {
          guard let product = selectedProduct else { return }
          
          isPurchasing = true
          defer { isPurchasing = false }
          
          do {
              let transaction = try await storeKit.purchase(product)
              if transaction != nil {
                  // Success - refresh user profile
                  await authVM.fetchProfile()
                  dismiss()
              }
          } catch {
              // Show error alert
          }
      }
      
      func restore() async {
          isPurchasing = true
          defer { isPurchasing = false }
          
          do {
              try await storeKit.restorePurchases()
              await authVM.fetchProfile()
              dismiss()
          } catch {
              // Show error alert
          }
      }
  }
  ```

- [ ] Create `ProductCard` component:
  ```swift
  struct ProductCard: View {
      let product: Product
      let isSelected: Bool
      
      var body: some View {
          HStack {
              VStack(alignment: .leading) {
                  Text(product.displayName)
                      .font(.headline)
                  Text(product.description)
                      .font(.caption)
                      .foregroundColor(.secondary)
              }
              
              Spacer()
              
              VStack(alignment: .trailing) {
                  Text(product.displayPrice)
                      .font(.title2)
                      .bold()
                  if product.subscription?.subscriptionPeriod.unit == .year {
                      Text("Save 17%")
                          .font(.caption)
                          .foregroundColor(.green)
                  }
              }
          }
          .padding()
          .background(
              RoundedRectangle(cornerRadius: 12)
                  .stroke(isSelected ? Color.primaryPurple : Color.gray, lineWidth: 2)
          )
      }
  }
  ```

### Phase 5: Settings Integration (30 mins)
- [ ] Add subscription management in `SettingsView.swift`:
  ```swift
  Section("Subscription") {
      if authVM.currentHousehold?.isPremiumActive == true {
          HStack {
              Text("Status")
              Spacer()
              Label("Premium", systemImage: "star.fill")
                  .foregroundColor(.yellow)
          }
          
          if let expiresAt = authVM.currentHousehold?.premiumExpiresAt {
              HStack {
                  Text("Renews")
                  Spacer()
                  Text(expiresAt, style: .date)
                      .foregroundColor(.secondary)
              }
          }
          
          Button("Manage Subscription") {
              // Open App Store subscriptions
              if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                  UIApplication.shared.open(url)
              }
          }
      } else {
          Button("Upgrade to Premium") {
              showPaywall = true
          }
      }
      
      Button("Restore Purchases") {
          Task {
              try? await StoreKitService.shared.restorePurchases()
              await authVM.fetchProfile()
          }
      }
  }
  ```

### Phase 6: Testing (2-3 hours)
- [ ] Sandbox Testing:
  - [ ] Create sandbox Apple ID in App Store Connect
  - [ ] Test monthly subscription purchase
  - [ ] Test annual subscription purchase
  - [ ] Test subscription cancellation
  - [ ] Test subscription renewal
  - [ ] Test expired subscription (accelerated time)
  - [ ] Test restore purchases
  - [ ] Test purchase on one device, restore on another
  - [ ] Test family sharing (if enabled)

- [ ] Server Validation Testing:
  - [ ] Verify receipt validation endpoint works
  - [ ] Check `premium_expires_at` updates correctly
  - [ ] Test webhook receives renewal notifications
  - [ ] Verify expired subscriptions downgrade correctly

- [ ] Edge Cases:
  - [ ] User cancels during purchase flow
  - [ ] Network error during purchase
  - [ ] Receipt validation fails
  - [ ] User already has active subscription
  - [ ] Multiple household members try to purchase

### Phase 7: Production Preparation (1 hour)
- [ ] Update server `.env`:
  ```bash
  # App Store Server API (optional for MVP)
  APPLE_APP_STORE_KEY_ID=ABC123DEF4
  APPLE_APP_STORE_ISSUER_ID=12345678-1234-1234-1234-123456789012
  APPLE_APP_STORE_PRIVATE_KEY=<path-to-key>
  
  # Subscription webhook (for renewals)
  APPLE_WEBHOOK_SECRET=<generated-secret>
  ```

- [ ] Add App Store Server Notifications (optional for MVP):
  - Go to App Store Connect → App → App Information
  - Enable "App Store Server Notifications"
  - Add URL: `https://api-pantrypal.subasically.me/api/subscriptions/webhook`
  - Set notification version: V2

- [ ] Add StoreKit configuration file to Xcode:
  - File → New → StoreKit Configuration File
  - Add products matching App Store Connect
  - Use for local testing without sandbox

---

## 🧪 Testing Strategy

### Test Plan:
1. **Happy Path:** User purchases monthly → Premium activates → Features unlock
2. **Cancellation:** User cancels → Premium remains until end of period → Downgrades gracefully
3. **Renewal:** Subscription renews → `premium_expires_at` extends → No user interruption
4. **Restore:** User reinstalls app → Taps "Restore" → Premium reactivates
5. **Multi-Device:** User buys on iPhone → Opens iPad → Premium syncs automatically
6. **Expired:** Subscription expires → User is Free tier → Can still view >25 items (read-only)

### Sandbox Accelerated Timeline:
- 1 week subscription = 3 minutes
- 1 month subscription = 5 minutes
- 1 year subscription = 1 hour

Use this to test renewals and expirations quickly.

---

## 📊 Success Metrics

After launching StoreKit:
- **Conversion Rate:** % of paywall views → purchases
- **Trial Conversion:** % of free trial users → paid (if trial enabled)
- **Churn Rate:** % of users who cancel vs renew
- **ARPU:** Average revenue per user (monthly)
- **Upgrade Triggers:** Which feature gate converts best (inventory limit, household invite, grocery auto-add)

---

## 🚨 Gotchas & Tips

1. **Sandbox Environment:**
   - Use separate Apple ID for sandbox testing
   - Clear sandbox purchase history regularly
   - Subscription renewals are accelerated (5 minutes for monthly)

2. **Receipt Validation:**
   - **Option A (MVP):** Trust client, validate format only (faster, less secure)
   - **Option B (Production):** Use App Store Server API (more secure, more complex)
   - Start with A, migrate to B post-launch

3. **StoreKit 2 vs StoreKit 1:**
   - Use StoreKit 2 (async/await, simpler API)
   - StoreKit 1 is legacy, don't use

4. **Family Sharing:**
   - Enable if you want to support it
   - Premium applies to entire household already (good fit)
   - Test with multiple family members

5. **Refunds:**
   - Apple handles refund requests
   - You'll receive webhook notification
   - Immediately revoke Premium on refund

6. **Transaction IDs:**
   - `transactionId`: Changes with each renewal
   - `originalTransactionId`: Never changes (use this as unique key)

---

## 🔗 Resources

- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit)
- [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi)
- [Implementing a Store (WWDC)](https://developer.apple.com/videos/play/wwdc2021/10114/)
- [App Store Server Notifications V2](https://developer.apple.com/documentation/appstoreservernotifications)
- [Testing In-App Purchases (Guide)](https://developer.apple.com/documentation/storekit/in-app_purchase/testing_in-app_purchases_with_sandbox)

---

## 📝 Post-Implementation

After StoreKit is live:
1. Monitor crash reports (StoreKit errors)
2. Track conversion funnel (paywall views → purchases)
3. A/B test pricing (monthly vs annual preference)
4. Add premium expiration warnings (7 days before)
5. Implement "last item" confirmation UX for free users
6. Consider adding one-time payment option (lifetime Premium)

---

## 🎯 Next Steps After StoreKit

1. **TestFlight Beta** (Week 3)
   - Invite 10-20 friends/family
   - Test household sharing end-to-end
   - Validate Premium purchase flow
   - Collect feedback on UX

2. **App Store Submission** (Week 3)
   - Screenshots for all devices
   - App preview video (optional)
   - Keyword optimization
   - Pricing finalization

3. **Launch** (Week 4)
   - Soft launch to small audience
   - Monitor metrics daily
   - Iterate on conversion rates
   - Validate revenue projections

---

**Status:** 🟡 Ready to implement  
**Blockers:** None  
**Risk:** Low (standard iOS pattern, well-documented)  
**Effort:** 8-12 hours over 2-3 days
