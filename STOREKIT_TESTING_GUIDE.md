# StoreKit Testing Guide

## Setup Steps

### 1. Add StoreKit Configuration to Xcode

1. Open `PantryPal.xcodeproj` in Xcode
2. Select the **PantryPal** scheme in the toolbar
3. Click **Edit Scheme** (or Product → Scheme → Edit Scheme)
4. Select **Run** in the left sidebar
5. Go to the **Options** tab
6. Under **StoreKit Configuration**, select `Configuration.storekit`
7. Click **Close**

### 2. Verify Products Load

Build and run the app:
1. Login/Register → Create or Join household
2. Add 26 items to hit the free limit (25)
3. Paywall should appear
4. Products should load and show:
   - **Annual: $49.99/year** (purple button, "Save 17%")
   - **Monthly: $4.99/month** (gray button)

### 3. Test Purchase Flow

**Happy Path:**
1. Tap "Subscribe for $49.99/year"
2. StoreKit prompt appears → Tap **Subscribe**
3. Loading indicator appears
4. Server validates receipt
5. Confetti animation plays 🎉
6. Paywall dismisses
7. Check Settings → Should show "Premium" badge (gradient)
8. Try adding item #26 → Should succeed

**Cancellation:**
1. Tap purchase button
2. Tap **Cancel** in StoreKit prompt
3. Paywall stays open (no error)
4. Can retry purchase

### 4. Test Restore Purchases

1. Delete app from simulator
2. Reinstall and login with same account
3. Add 26 items to trigger paywall
4. Tap **Restore Purchases**
5. Loading indicator
6. Should show success toast and dismiss
7. Premium features unlocked

### 5. Test Error Handling

**No Products Available:**
- Disable internet → Products fail to load
- Should see error alert: "Failed to load products"

**Server Validation Failure:**
- Check Xcode console for "❌ [StoreKit] Failed to verify with server"
- Purchase still completes locally (StoreKit listener will retry)

## Sandbox Testing (Real Devices)

### 1. Create Sandbox Test Account
1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. Users and Access → Sandbox Testers
3. Click **+** → Add test account (use fake email)
4. Remember password (needed for purchase)

### 2. Configure Device
1. Settings → App Store → Sandbox Account
2. Sign in with test account
3. **DO NOT** use real Apple ID for testing

### 3. Test Purchase Flow
1. Build app to device (with sandbox account signed in)
2. Trigger paywall → Purchase
3. Use sandbox account password when prompted
4. Verify Premium unlocked
5. Check server logs for validation

### 4. Test Restore
1. Delete app
2. Reinstall → Login
3. Restore Purchases
4. Should work with sandbox account

### 5. Test Subscription Management
1. Settings → App Store → Manage Subscriptions
2. Should see "PantryPal Premium Monthly/Annual"
3. Can cancel → App should handle expiration gracefully

## Console Logs to Watch

**Successful Purchase:**
```
🛒 [StoreKit] Loading products...
✅ [StoreKit] Loaded monthly: $4.99
✅ [StoreKit] Loaded annual: $49.99
🛒 [StoreKit] Starting purchase: com.pantrypal.premium.annual
✅ [StoreKit] Purchase successful: <transaction-id>
🔐 [StoreKit] Verifying transaction with server: <transaction-id>
✅ [StoreKit] Server validated subscription. Premium expires: <date>
✅ [Paywall] Purchase successful
```

**Server Logs:**
```
🍎 [StoreKit] Validating receipt for user <id>
📝 [StoreKit] Updating household <id> with premium_expires_at: <date>
✅ [StoreKit] Premium activated for household <id>
```

## Known Issues & Troubleshooting

### Products Not Loading
- **Check:** Configuration.storekit added to scheme?
- **Check:** Product IDs match: `com.pantrypal.premium.monthly` and `com.pantrypal.premium.annual`
- **Check:** Internet connection available?

### Purchase Completes But Premium Not Unlocked
- **Check:** Server logs for validation errors
- **Check:** User has household_id (not NULL)?
- **Check:** AuthViewModel.refreshCurrentUser() called after purchase?

### Restore Shows "No active subscriptions"
- Expected if you haven't purchased yet
- With sandbox: Must purchase first, then restore will work

### Confetti Not Showing
- **Check:** ConfettiCenter initialized in app root?
- **Check:** Environment object passed to PaywallView?

## Next Steps After Testing

1. ✅ Verify purchase flow works end-to-end
2. ✅ Verify restore purchases works
3. ✅ Test error handling (cancellation, network errors)
4. 📱 Test on real device with sandbox account
5. 🚀 Submit for TestFlight review
6. 👥 Beta test with friends/family
7. 🎉 Launch on App Store

## Production Checklist

Before submitting to App Store:
- [ ] Product IDs match App Store Connect exactly
- [ ] App Store screenshots (1320 × 2868)
- [ ] App description highlighting Premium features
- [ ] Privacy policy URL (household sharing data)
- [ ] Support URL/email
- [ ] Test on multiple devices (iPhone, iPad)
- [ ] Test with poor network conditions
- [ ] Verify analytics/crash reporting (if any)
- [ ] Remove DEBUG simulate Premium button (or wrap in `#if DEBUG`)

