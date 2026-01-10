# PantryPal Sandbox Testing Guide

Comprehensive guide for testing Premium subscriptions and freemium features in the Apple sandbox environment.

## Table of Contents
1. [Environment Setup](#environment-setup)
2. [Testing Environments Comparison](#testing-environments-comparison)
3. [Pre-Test Checklist](#pre-test-checklist)
4. [Test Scenarios](#test-scenarios)
5. [Troubleshooting](#troubleshooting)

---

## Environment Setup

### Prerequisites
- ✅ Active Apple Developer Program account
- ✅ Paid Applications Agreement signed
- ✅ In-App Purchases configured in App Store Connect (3 products: Monthly, Annual, Annual Discounted)
- ✅ Sandbox Apple Accounts created in App Store Connect
- ✅ Developer Mode enabled on test devices
- ✅ Production database reset for clean testing

### Sandbox Apple Accounts
Create at least 2 sandbox accounts for testing:

| Account | Purpose | Device |
|---------|---------|--------|
| webalenko@icloud.com (sandbox version) | Primary tester | iPad |
| alensubasic@gmail.com (sandbox version) | Secondary tester (multi-device/household) | iPhone |

### Signing In to Sandbox (Development Build)

**iOS Development Build:**
1. Build and run from Xcode
2. Navigate to **Settings → Developer**
3. Scroll to **Sandbox Apple Account** section
4. Sign in with sandbox credentials
5. Verify `[Environment: Sandbox]` appears on first purchase

**Important:** Do NOT sign out of your production Apple Account in Settings → [Your Name]. Keep it signed in. Sandbox account is separate under Developer settings.

### Sandbox Settings Configuration

Access sandbox controls:
- **Settings → Developer → Sandbox Apple Account → Manage**

Key settings:
- **Renewal Rate**: 5 minutes (recommended for balanced testing)
  - 3 min = rapid testing (36 min full cycle)
  - 5 min = balanced (60 min full cycle) ✅
  - 15 min = slow (180 min = 3 hours)
  - 30 min = very slow (360 min = 6 hours)
  - 60 min = production-like (720 min = 12 hours)

- **Interrupted Purchases**: OFF (unless specifically testing)
- **Clear Purchase History**: Use before each major test

---

## Testing Environments Comparison

### Sandbox (Current Environment)
- **Purpose**: Rapid testing with accelerated expiration
- **Expiration**: 60x faster than production
  - 1 year = 1 hour
  - 1 month = 5 minutes
  - 1 week = ~1.5 minutes
  - 1 day = ~1.5 seconds
- **Renewals**: Up to 12 automatic renewals
- **Renewal Rate**: Configurable (3/5/15/30/60 minutes)
- **Full Cycle**: ~60 minutes at 5-minute renewal rate
- **Advanced Features**:
  - Simulate billing failures
  - Simulate billing retry states
  - Simulate billing grace period
  - Clear purchase history
  - Test win-back offers

**Use Cases:**
- Expiration behavior testing
- Billing retry/failure scenarios
- Rapid iteration on payment flows
- Server notification testing

### TestFlight (Future Testing)
- **Purpose**: Realistic multi-day testing
- **Expiration**: All durations renew every **24 hours**
- **Renewals**: Up to 6 automatic renewals (7 days total)
- **Auto-Cancel**: Subscription auto-cancels on day 7
- **Full Cycle**: 7 days regardless of subscription duration
- **No Advanced Features**: Cannot simulate failures or clear history

**Use Cases:**
- Beta tester experience validation
- Multi-day subscription lifecycle
- Realistic user flows over time
- Pre-production validation

### Production
- **Purpose**: Real customer transactions
- **Expiration**: Normal durations (monthly, yearly, etc.)
- **Renewals**: Unlimited (while customer subscribed)
- **Billing**: Real charges to customer credit card

---

## Pre-Test Checklist

Before starting each test scenario:

### 1. Reset Database
```bash
cd /Users/subasically/Desktop/github/PantryPal
./server/scripts/reset-database.sh --force
```
Expected: Fresh database with clean households, no subscriptions

### 2. Clear Sandbox Purchase History
**Settings → Developer → Sandbox Apple Account → Manage → Clear Purchase History**

Sign out and back in to sandbox account to clear cache.

### 3. Delete and Reinstall App
```bash
# Delete PantryPal from device
# Rebuild from Xcode
```
Expected: Fresh install, no SwiftData cache

### 4. Verify Sandbox Account
**Settings → Developer → Sandbox Apple Account**

Confirm correct sandbox account is signed in.

### 5. Verify API Connectivity
Open app and trigger any API call (login/register).

Check logs for successful connection to `https://api-pantrypal.subasically.me`

### 6. Set Renewal Rate
**Settings → Developer → Sandbox Apple Account → Manage**

Set renewal rate to **5 minutes** (unless testing specific scenario).

---

## Test Scenarios

### Scenario 1: Free Tier Solo User - Limit Enforcement

**Objective**: Verify free tier limits (25 inventory + 25 grocery items) are enforced correctly.

**Prerequisites**:
- Fresh database reset
- Sandbox purchase history cleared
- App deleted and reinstalled

**Steps**:
1. Register new user (use sandbox email)
2. Create/auto-join household
3. Add 25 inventory items (use Quick Add scanner or manual entry)
4. Attempt to add 26th inventory item
5. **Expected**: Paywall appears with "Upgrade to Premium" message
6. Dismiss paywall
7. Add 25 grocery items
8. Attempt to add 26th grocery item
9. **Expected**: Paywall appears again

**Success Criteria**:
- ✅ Free tier allows exactly 25 inventory items
- ✅ Free tier allows exactly 25 grocery items
- ✅ Paywall triggers on 26th item attempt
- ✅ Paywall shows correct messaging
- ✅ User can dismiss paywall and continue using free features

**Debug**:
- Check iOS logs for "Limit reached" messages
- Check server logs for 403 responses with `LIMIT_EXCEEDED` error code
- Verify database: `SELECT COUNT(*) FROM inventory WHERE household_id = ?`

---

### Scenario 2: Premium Purchase Flow - First-Time Buyer

**Objective**: Complete end-to-end Premium purchase and verify activation.

**Prerequisites**:
- Fresh database reset
- Sandbox purchase history cleared
- Free tier limits tested (Scenario 1)

**Steps**:
1. Register new user
2. Add 25 items to trigger paywall
3. From paywall, tap "View Premium Plans"
4. Select **Annual** subscription ($49.99/year)
5. Confirm Face ID/Touch ID prompt
6. Wait for purchase confirmation
7. **Expected**: Confetti animation + "Welcome to Premium!" message
8. Verify Premium badge shows in Settings → Account
9. Add 26th inventory item (should work now)
10. Add 50+ items total
11. Verify no paywall appears

**Success Criteria**:
- ✅ Purchase completes without errors
- ✅ Confetti animation plays
- ✅ Premium status shows immediately in UI
- ✅ Can add unlimited items
- ✅ Server reflects Premium status (check `subscriptions` table)
- ✅ `expires_at` shows correct future date

**Debug**:
- iOS logs: `[StoreKit] Purchase initiated`, `[StoreKit] Transaction verified`
- Server logs: `POST /api/subscriptions/validate-receipt`, `200 OK`
- Database: `SELECT * FROM subscriptions WHERE household_id = ?`

---

### Scenario 3: Subscription Renewal Cycle - 12 Renewals

**Objective**: Observe automatic subscription renewals over full sandbox lifecycle.

**Prerequisites**:
- Premium purchased (Scenario 2)
- Renewal rate set to **5 minutes**

**Timeline**:
| Time | Event | Expected Behavior |
|------|-------|-------------------|
| 0:00 | Initial purchase | Premium activated |
| 0:05 | Renewal 1 | Silent renewal, no UI change |
| 0:10 | Renewal 2 | Silent renewal |
| 0:15 | Renewal 3 | Silent renewal |
| 0:20 | Renewal 4 | Silent renewal |
| 0:25 | Renewal 5 | Silent renewal |
| 0:30 | Renewal 6 | Silent renewal |
| 0:35 | Renewal 7 | Silent renewal |
| 0:40 | Renewal 8 | Silent renewal |
| 0:45 | Renewal 9 | Silent renewal |
| 0:50 | Renewal 10 | Silent renewal |
| 0:55 | Renewal 11 | Silent renewal |
| 1:00 | Renewal 12 (final) | Silent renewal |
| 1:05 | **Expiration** | Premium expires, free tier enforced |

**Steps**:
1. Purchase Premium at T=0
2. Keep app open or check periodically
3. Monitor iOS logs for renewal transactions
4. At each 5-minute mark, verify Premium still active
5. After final renewal (~60 minutes), wait 5 more minutes
6. **Expected**: Premium expires, free tier enforced
7. Add items to verify limits re-apply
8. **Expected**: Paywall appears on 26th item

**Success Criteria**:
- ✅ 12 successful renewals occur at 5-minute intervals
- ✅ No interruptions or billing failures
- ✅ Premium status maintained throughout
- ✅ Expiration occurs after 12th renewal
- ✅ Free tier limits enforced after expiration
- ✅ Paywall shows "Renew Premium" instead of "Upgrade"

**Debug**:
- iOS logs: `[StoreKit] Transaction updated`, `ACTIVE/EXPIRED` status
- Server logs: Renewal notifications from App Store Server API
- Database: `SELECT * FROM subscriptions ORDER BY created_at DESC LIMIT 13`

---

### Scenario 4: Expired Premium - Win-Back Flow

**Objective**: Verify graceful degradation and re-subscription flow for expired users.

**Prerequisites**:
- Premium expired (after Scenario 3)
- User has > 25 items from Premium period

**Steps**:
1. After expiration, open app
2. Navigate to Inventory
3. **Expected**: Existing items still visible (no deletion)
4. Attempt to add 26th new item
5. **Expected**: Paywall appears with "Renew Premium" messaging
6. From paywall, tap "Renew Premium"
7. Select Annual subscription again
8. Confirm purchase
9. **Expected**: Confetti + "Welcome Back to Premium!" message
10. Verify can add items again

**Success Criteria**:
- ✅ Existing items not deleted after expiration
- ✅ Read-only access to > 25 items maintained
- ✅ Paywall shows "Renew" instead of "Upgrade"
- ✅ Re-subscription works smoothly
- ✅ Premium reactivated immediately

**Debug**:
- iOS logs: `[StoreKit] Win-back purchase`, `[Auth] Premium reactivated`
- Server logs: New subscription row created or existing updated
- Database: `SELECT * FROM subscriptions WHERE household_id = ? ORDER BY created_at DESC`

---

### Scenario 5: Multi-Device Sync - Premium Household Sharing

**Objective**: Verify Premium status syncs across household members on different devices.

**Prerequisites**:
- Device 1 (iPad): webalenko@icloud.com with Premium
- Device 2 (iPhone): alensubasic@gmail.com, fresh install
- Both devices signed into sandbox accounts

**Steps**:
1. **Device 1**: Purchase Premium (if not already active)
2. **Device 1**: Settings → Household Sharing → Generate invite code
3. **Device 2**: Register new user (alensubasic@gmail.com)
4. **Device 2**: Join household with invite code from Device 1
5. **Device 2**: Wait for sync to complete
6. **Device 2**: Check Settings → Account
7. **Expected**: Premium badge shows (shared from Device 1)
8. **Device 2**: Add 50+ inventory items
9. **Expected**: No paywall appears
10. **Device 1**: Verify items from Device 2 appear
11. **Device 1**: Add items, verify they appear on Device 2

**Success Criteria**:
- ✅ Premium status visible on Device 2 after joining household
- ✅ Both devices can add unlimited items
- ✅ Items sync bidirectionally within ~10 seconds
- ✅ No duplicate items created
- ✅ Locations sync correctly

**Debug**:
- Both devices: `[Sync] Received X changes`, `[Sync] Applied X changes`
- Server logs: `GET /api/sync/changes` from both household members
- Database: `SELECT * FROM users WHERE household_id = ?` (both users same household)

---

### Scenario 6: Offline Mode - Premium Limits Cached

**Objective**: Verify Premium status persists offline and limits enforced correctly.

**Prerequisites**:
- Device with Premium active
- Recent successful sync

**Steps**:
1. Enable Airplane Mode
2. Open app
3. **Expected**: Premium badge still shows
4. Add 10 new inventory items
5. **Expected**: Items added to local SwiftData cache
6. Add 20 more items (30 total offline)
7. **Expected**: All items saved locally, no paywall
8. Disable Airplane Mode
9. Wait for sync
10. **Expected**: All 30 items sync to server
11. Verify items appear on other devices

**Success Criteria**:
- ✅ Premium status cached and available offline
- ✅ Unlimited items can be added offline
- ✅ Items queued in SwiftData pending actions
- ✅ Sync completes successfully when online
- ✅ No conflicts or duplicates after sync

**Debug**:
- iOS logs: `[ActionQueue] Queued 30 pending actions`, `[Sync] Uploaded pending actions`
- Server logs: `POST /api/sync/changes` with 30 new items
- Database: `SELECT * FROM inventory WHERE household_id = ? AND created_at > ?`

---

### Scenario 7: Billing Failure Simulation - Retry States

**Objective**: Test app behavior when subscription renewal fails and enters billing retry.

**Prerequisites**:
- Premium active
- Renewal rate set to 5 minutes
- Sandbox advanced settings configured

**Steps**:
1. Purchase Premium
2. Wait for first renewal (T=5 min)
3. **In Sandbox Settings**: Settings → Developer → Sandbox Apple Account → Manage
4. Enable **Billing Problem** simulation (if available)
5. Wait for next renewal attempt
6. **Expected**: Renewal fails, enters billing retry state
7. Check app UI
8. **Expected**: Warning banner shows "Billing Issue - Update Payment"
9. In app, tap "Update Payment"
10. **Expected**: Opens App Store payment management
11. Resolve billing issue in sandbox
12. **Expected**: Subscription reactivates

**Success Criteria**:
- ✅ App detects billing retry state
- ✅ Warning UI shows without blocking access
- ✅ User can continue using Premium during retry period
- ✅ After grace period, Premium expires if not resolved
- ✅ Re-subscription works after resolution

**Debug**:
- iOS logs: `[StoreKit] Transaction state: billing_retry`, `[Auth] Billing issue detected`
- Server logs: App Store Server Notification with `DID_FAIL_TO_RENEW`
- Database: `SELECT * FROM subscriptions WHERE status = 'billing_retry'`

---

### Scenario 8: Refund Request - Premium Revocation

**Objective**: Verify app handles refund scenario correctly and revokes Premium access.

**Prerequisites**:
- Active Premium subscription
- Purchase within refund window

**Steps**:
1. Purchase Premium
2. Use for 10 minutes (add items, test features)
3. Request refund via App Store
4. **Sandbox**: Use reportaproblem.apple.com with sandbox credentials
5. Submit refund request
6. **Expected**: Refund approved instantly in sandbox
7. Open app
8. **Expected**: Premium status revoked immediately
9. Attempt to add 26th item
10. **Expected**: Paywall appears

**Success Criteria**:
- ✅ App receives refund notification from server
- ✅ Premium status revoked immediately
- ✅ Free tier limits enforced
- ✅ User data not deleted (items remain visible)
- ✅ Can re-purchase Premium if desired

**Debug**:
- iOS logs: `[StoreKit] Refund transaction received`
- Server logs: App Store Server Notification with `REFUND`
- Database: `SELECT * FROM subscriptions WHERE status = 'refunded'`

---

### Scenario 9: Family Sharing (Future Feature)

**Objective**: If Family Sharing is enabled, verify household members share Premium status.

**Status**: Not yet implemented in PantryPal (household sharing is app-level, not Apple Family Sharing).

**Skip for now** - Document for future reference.

---

### Scenario 10: Product Identifier Validation

**Objective**: Verify app fetches correct product identifiers from App Store Connect.

**Prerequisites**:
- Fresh app launch

**Steps**:
1. Launch app
2. Navigate to Settings → Premium (or trigger paywall)
3. Check iOS logs
4. **Expected**: `[StoreKit] Fetched products: 3`, `[StoreKit] Product IDs: [...]`
5. Verify all 3 products load:
   - `me.subasically.pantrypal.premium.monthly`
   - `me.subasically.pantrypal.premium.annual`
   - `me.subasically.pantrypal.premium.annual.discounted`
6. Verify prices display correctly in UI
7. Verify product descriptions show

**Success Criteria**:
- ✅ All 3 products fetch successfully
- ✅ Prices display in sandbox account's region currency
- ✅ No "Product not found" errors
- ✅ Product titles and descriptions render correctly

**Debug**:
- iOS logs: `[StoreKit] Product request completed`, `[StoreKit] Products: [...]`
- If failed: Check App Store Connect configuration, ensure products are "Ready to Submit"

---

## Troubleshooting

### Issue: Purchase Stuck on "Processing"

**Symptoms**: Purchase spinner never completes, transaction hangs.

**Causes**:
- App killed before `finishTransaction()` called
- Network interruption during verification
- Server validation endpoint down

**Solutions**:
1. Force quit app and reopen
2. Check `Transaction.currentEntitlements` in StoreKit 2
3. Verify server logs: `POST /api/subscriptions/validate-receipt`
4. Clear sandbox purchase history and retry

---

### Issue: Premium Shows as Expired Immediately

**Symptoms**: Purchase completes but shows "EXPIRED" status in logs.

**Causes**:
- **Expected in sandbox**: 1-year subscription expires in 1 hour
- Device clock incorrect

**Solutions**:
- Verify sandbox renewal rate setting
- Check device date/time (must be automatic)
- Use "Simulate Premium" debug button for testing (adds 1 year from current time)

---

### Issue: Items Not Syncing Across Devices

**Symptoms**: Items added on Device 1 don't appear on Device 2.

**Causes**:
- Sync cursor stuck
- Different households (not joined correctly)
- Network connectivity issues

**Solutions**:
1. Settings → Debug → Force Full Sync Now
2. Verify both devices in same household: `SELECT * FROM users WHERE household_id = ?`
3. Check sync logs: `[Sync] Polling for changes...`, `[Sync] Applied X changes`
4. Reset sync cursor: Delete app and reinstall

---

### Issue: Location Validation Error

**Symptoms**: "Location not found or does not belong to this household" when scanning items.

**Causes**:
- Old household location IDs cached
- Sync not completed after household join
- Database reset without app reinstall

**Solutions**:
1. Delete app and reinstall (clears SwiftData cache)
2. Settings → Debug → Force Full Sync Now
3. Check server logs for locationId mismatch
4. Verify household has 7 default locations: `SELECT * FROM locations WHERE household_id = ?`

---

### Issue: Paywall Not Appearing at 26th Item

**Symptoms**: Can add > 25 items without Premium.

**Causes**:
- Premium mistakenly activated
- Server limits check not working
- Client-side limit check skipped

**Solutions**:
1. Check Settings → Account: Should show "Free" tier
2. Verify database: `SELECT * FROM subscriptions WHERE household_id = ?` (should be empty or expired)
3. Check server logs: Should see `POST /api/inventory` with 403 response on 26th item
4. Rebuild app with latest code

---

### Issue: 502 Bad Gateway After Server Deploy

**Symptoms**: API unreachable through domain, works locally.

**Causes**:
- Docker container not connected to `web` network
- Reverse proxy misconfiguration

**Solutions**:
1. SSH to VPS: `ssh root@62.146.177.62`
2. Check docker-compose.yml has `networks: - web`
3. Verify external network exists: `docker network ls | grep web`
4. Restart containers: `cd /root/pantrypal-server/server && docker compose down && docker compose up -d`
5. Test: `curl https://api-pantrypal.subasically.me/health` (should return `{"status":"ok"}`)

---

## Success Metrics

After completing all scenarios, verify:

- ✅ Free tier limits enforced correctly (25 inventory + 25 grocery)
- ✅ Premium purchase flow works end-to-end
- ✅ Subscription renewals occur automatically (up to 12 in sandbox)
- ✅ Expiration handled gracefully (no data loss, limits re-applied)
- ✅ Win-back flow works for expired users
- ✅ Premium status syncs across household members
- ✅ Offline mode respects Premium status
- ✅ Billing failures handled with user-friendly UI
- ✅ Refunds revoke Premium immediately
- ✅ Product fetching works reliably

---

## Next Steps

After sandbox testing complete:

1. **Document Bugs**: Create issues in GitHub for any failures
2. **Fix Critical Bugs**: Priority on purchase flow, sync, and limits
3. **TestFlight Prep**: Upload build for beta testing
4. **TestFlight Testing**: Run 7-day subscription lifecycle test
5. **Production Release**: Submit for App Store review

---

## Appendix: Quick Reference

### Renewal Rate Cheat Sheet
| Sandbox Setting | Real Duration | Sandbox Duration | Full Cycle (12 renewals) |
|----------------|---------------|------------------|--------------------------|
| 3 minutes | 1 year | 3 min | ~36 minutes |
| 5 minutes | 1 year | 5 min | ~60 minutes |
| 15 minutes | 1 year | 15 min | ~3 hours |
| 30 minutes | 1 year | 30 min | ~6 hours |
| 60 minutes | 1 year | 60 min | ~12 hours |

### Database Quick Queries
```sql
-- Check subscription status
SELECT * FROM subscriptions WHERE household_id = '9bdeb6d2-d823-4e95-bb7a-05082aeed590';

-- Count inventory items
SELECT COUNT(*) FROM inventory WHERE household_id = '9bdeb6d2-d823-4e95-bb7a-05082aeed590';

-- Check household members
SELECT * FROM users WHERE household_id = '9bdeb6d2-d823-4e95-bb7a-05082aeed590';

-- Verify default locations
SELECT * FROM locations WHERE household_id = '9bdeb6d2-d823-4e95-bb7a-05082aeed590';
```

### Server Commands
```bash
# Reset database
./server/scripts/reset-database.sh --force

# View server logs
ssh root@62.146.177.62 "cd /root/pantrypal-server/server && docker compose logs -f pantrypal-api"

# Restart server
ssh root@62.146.177.62 "cd /root/pantrypal-server/server && docker compose restart"

# Health check
curl https://api-pantrypal.subasically.me/health
```

---

**Document Version**: 1.0  
**Last Updated**: January 10, 2026  
**Sandbox Renewal Rate**: 5 minutes  
**Testing Status**: Ready for Scenario 1
