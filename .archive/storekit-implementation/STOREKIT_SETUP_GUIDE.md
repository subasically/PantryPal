# StoreKit Setup Guide for TestFlight/Production

## Current Status
✅ Code integrated (PaywallView + StoreKitService)  
✅ Local .storekit configuration file created  
❌ Products NOT configured in App Store Connect (this is why buttons do nothing!)

## Why Buttons Don't Work in TestFlight
In TestFlight, StoreKit needs **real products configured in App Store Connect**. The local Configuration.storekit file only works for Xcode debugging with StoreKit Testing enabled.

## Step-by-Step Setup

### 1. Create Subscription Products in App Store Connect

Go to: https://appstoreconnect.apple.com

1. Navigate to: **App Store Connect** → **My Apps** → **PantryPal** → **Monetization** → **Subscriptions**

2. Click **"+"** to create a new Subscription Group:
   - **Name**: "Premium"
   - Click **Create**

3. Inside the "Premium" group, click **"+"** to add subscriptions:

#### Monthly Subscription
- **Reference Name**: PantryPal Premium Monthly
- **Product ID**: `com.pantrypal.premium.monthly` (MUST match exactly!)
- **Duration**: 1 Month
- **Price**: $4.99 USD (Tier 5)
- **Localization (English US)**:
  - Display Name: PantryPal Premium Monthly
  - Description: Unlimited items and household sharing
- Click **Save**

#### Annual Subscription
- **Reference Name**: PantryPal Premium Annual  
- **Product ID**: `com.pantrypal.premium.annual` (MUST match exactly!)
- **Duration**: 1 Year
- **Price**: $49.99 USD (Tier 50)
- **Localization (English US)**:
  - Display Name: PantryPal Premium Annual
  - Description: Unlimited items and household sharing
- Click **Save**

### 2. Configure Subscription Details

For both subscriptions, configure:

#### App Store Information
- **Subscription Display Name**: (Already set above)
- **Subscription Description**: "Get unlimited inventory items and sync with your household members in real-time."

#### Review Information
- **Screenshot**: Upload a screenshot of the paywall or premium features
- **Review Notes**: "Premium subscription unlocks unlimited items and household sharing. Free users limited to 25 items."

#### Subscription Pricing
- **Base Plan**: Already set ($4.99 monthly / $49.99 yearly)
- Leave introductory offers blank for now

### 3. Submit Subscriptions for Review

1. Both subscriptions will show status: **"Missing Metadata"** or **"Ready to Submit"**
2. Click **"Submit for Review"** on each one
3. Wait for Apple approval (usually 24-48 hours)

### 4. Sync StoreKit Configuration in Xcode

1. Open **PantryPal.xcodeproj** in Xcode
2. Select **Configuration.storekit** in the file navigator
3. Go to: **Editor** → **Sync with App Store Connect**
4. Xcode will fetch your configured products and update the file

### 5. Configure StoreKit in Build Settings

1. In Xcode, select **PantryPal** project
2. Select **PantryPal** target
3. Go to **Signing & Capabilities** tab
4. Add capability: **In-App Purchase** (if not already added)
5. Go to **Build Settings** tab
6. Search for "StoreKit"
7. Set **StoreKit Configuration File** to: `Configuration.storekit`

### 6. Test in Sandbox (Before TestFlight)

Before submitting to TestFlight, test locally:

1. In Xcode, select: **Product** → **Scheme** → **Edit Scheme**
2. Under **Run** → **Options** tab
3. Set **StoreKit Configuration** to: `Configuration.storekit`
4. Run on a real device (not simulator for best results)
5. Test purchase flow - it will use the local .storekit file

### 7. TestFlight Testing

Once products are **"Ready for Sale"** in App Store Connect:

1. Build and upload a new TestFlight build
2. Wait for "Processing" to complete
3. Install on a test device
4. **Create a Sandbox Tester Account**:
   - Go to: **App Store Connect** → **Users and Access** → **Sandbox Testers**
   - Click **"+"** and create a test Apple ID
   - **Important**: Use a NEW email that's never been an Apple ID before!
   - Example: `pantrypal.test1@icloud.com`

5. **On your test device**:
   - Sign OUT of your real Apple ID in Settings → App Store
   - Open PantryPal from TestFlight
   - Trigger the paywall
   - When prompted, sign in with your **Sandbox Tester** account
   - Complete the purchase (you won't be charged - it's a test!)

### 8. Verify Server Integration

After successful sandbox purchase:

1. Check server logs: `docker-compose logs -f pantrypal-api`
2. Verify receipt validation endpoint was called
3. Check database: `premium_expires_at` should be set
4. Verify confetti shows and paywall dismisses
5. Verify unlimited items work

## Common Issues

### "Cannot connect to App Store"
- Products not approved yet (wait for App Store review)
- Not signed in with Sandbox Tester account
- Device still using production Apple ID

### "Product not found" / Buttons still don't work
- Product IDs in code don't match App Store Connect
- Products not in "Ready for Sale" status
- Forgot to sync .storekit with App Store Connect

### Purchase succeeds but Premium not activated
- Server receipt validation failing (check logs)
- `premium_expires_at` not being set correctly
- Client not refreshing user data after purchase

## Product ID Reference

**In Code** (`StoreKitService.swift`):
```swift
private let monthlyProductID = "com.pantrypal.premium.monthly"
private let annualProductID = "com.pantrypal.premium.annual"
```

**In App Store Connect**:
- Monthly: `com.pantrypal.premium.monthly` - $4.99/month
- Annual: `com.pantrypal.premium.annual` - $49.99/year

**THESE MUST MATCH EXACTLY!**

## Next Steps

1. ✅ Set up products in App Store Connect (following steps above)
2. ⏳ Wait for Apple approval (24-48 hours)
3. ✅ Sync Configuration.storekit with App Store Connect
4. ✅ Create Sandbox Tester accounts
5. ✅ Test in TestFlight with sandbox account
6. ✅ Verify server integration works
7. ✅ Ship to production! 🚀

## Production Checklist

Before launching to real users:

- [ ] Both subscription products approved in App Store Connect
- [ ] Tested purchase flow in TestFlight sandbox
- [ ] Tested restore purchases flow
- [ ] Verified server receipt validation works
- [ ] Verified `premium_expires_at` updates correctly
- [ ] Tested subscription renewal (wait 5 minutes in sandbox)
- [ ] Tested subscription cancellation
- [ ] Added "Terms of Use" and "Privacy Policy" links to paywall
- [ ] App Store Review Information includes test account for premium features
