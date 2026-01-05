# PantryPal Testing Guide

## 🧪 Test Plan

### Important Notes
- **Premium Sandbox Timing:** Monthly = 5 minutes, Annual = 1 hour
- **Test Order Matters:** Follow Free → Premium → Multi-user sequence to validate upgrade path
- **Database Reset:** Use `./server/scripts/reset-database.sh` for fresh start

---

## Test 1: Free Tier - Solo User (25 item limit)

### Setup
1. Delete app from iPhone
2. Reinstall from Xcode
3. Sign in with new Apple ID or email (User A)
4. Household auto-created on first launch

### Test Cases
- ✅ Add 1-24 items → Should work fine
- ✅ Add 25th item → Should work (at limit)
- ❌ Try to add 26th item → Should show Premium paywall
- ✅ Pull to refresh → Items sync correctly
- ✅ Edit/delete items → Should work (still solo user, no Premium needed)

### Expected Behavior
- Free users can manage up to 25 items total (inventory + grocery combined)
- Solo users don't need Premium for write operations
- Paywall appears when trying to exceed limit

---

## Test 2: Premium - Single User

### Setup
1. Same user from Test 1
2. Purchase Premium (recommend Annual for 1-hour test duration)

### Test Cases
- ✅ Premium status updates immediately after purchase
- ✅ Add 26th+ items → Should work (no limit with Premium)
- ✅ Pull to refresh → All items sync correctly
- ✅ Items persist after sync
- ✅ Premium badge visible in Settings

### Expected Behavior
- No app restart needed after purchase
- Unlimited items immediately available
- Premium status reflected across all screens

---

## Test 3: Premium - Two Users (Household Sharing)

### Setup
1. Keep User A (Premium) on iPhone
2. Install app on iPad
3. Sign in with different Apple ID/email (User B)
4. User B joins User A's household with invite code

### Test Cases
- ✅ User B can see User A's items immediately (read access)
- ✅ User A adds item → Syncs to User B within seconds
- ✅ User B adds item → Should work (User A's Premium covers household)
- ✅ Both users can edit/delete any items
- ✅ Changes sync bidirectionally
- ✅ Locations sync to both devices
- ✅ Grocery list syncs to both devices

### Expected Behavior
- One Premium subscription covers entire household
- All members have full read/write access
- Sync happens within seconds (pull to refresh forces immediate sync)
- Household members count visible in Settings → Household Sharing

---

## Test 4: Free Tier - Two Users (Writes Blocked)

### Setup
1. Wait for Premium to expire (1 hour for Annual) OR use Settings → Delete Household Data
2. Restart fresh with User A (no Premium) + User B in same household

### Test Cases
- ✅ Both users can READ all items
- ❌ User A tries to add item → Premium paywall
- ❌ User B tries to add item → Premium paywall
- ❌ Edit/delete attempts → Premium paywall
- ✅ Sync still works (read-only mode)
- ✅ Can view grocery list and locations

### Expected Behavior
- Multi-user households require Premium for write operations
- Reading/syncing always works regardless of Premium status
- Clear paywall messaging: "Household sharing is a Premium feature"

---

## Test 5: Offline → Online Sync

### Test Cases
1. Enable Airplane Mode on iPhone
2. Add 3 items while offline
3. Disable Airplane Mode
4. Items auto-sync to server (check console logs)
5. Pull to refresh on iPad → Items appear

### Expected Behavior
- Items saved locally in SwiftData while offline
- Action queue enqueues operations
- Auto-sync triggers when online
- Changes propagate to all devices

### Watch For
- Console logs: "Action create processed successfully"
- Action queue: "Processing X pending actions..."
- Sync logs: "Received X changes"

---

## Test 6: Grocery List Sync

### Test Cases
1. User A adds item to pantry
2. User A removes last one → "Add to grocery list?" prompt appears
3. Confirm add to grocery
4. User B pulls to refresh → Grocery item appears
5. User B checks off grocery item
6. User A pulls to refresh → Item removed from grocery

### Expected Behavior
- Grocery items sync between devices
- Check-off actions sync immediately
- Premium users: Auto-add to grocery when qty → 0
- Free users: Manual prompt to add

---

## Test 7: Location Sync

### Test Cases
1. User A: Settings → Storage Locations → Add location (e.g., "Garage Freezer")
2. User B: Pull to refresh
3. New location appears in User B's location picker
4. Both users can add items to new location

### Expected Behavior
- Default locations created on household setup: Kitchen, Pantry, Refrigerator, Freezer
- Custom locations sync to all household members
- Location changes visible immediately after sync

---

## 🔍 Key Things to Watch For

### Console Logs
- **Sync:** `📦 [SyncService] Received X changes` / `✅ Applied X changes`
- **Action Queue:** `Action create processed successfully` vs `Failed to process action`
- **Premium Check:** Look for 403 errors triggering paywall
- **Database:** `📂 [Database] Opening database at: /app/db/pantrypal.db`

### Timing
- **Sandbox Subscriptions:**
  - Monthly: 5 minutes real time
  - Annual: 1 hour real time
- **Sync Intervals:**
  - Pull to refresh: Immediate
  - Background sync: ~15 seconds minimum interval
  - Action queue: Immediate after operations

### Verification
- **Household ID:** Settings → Household Sharing → Check all users have same household
- **Premium Status:** Settings → Account → Premium badge visible when active
- **Item Count:** Pantry title shows "(X)" count
- **Sync Cursor:** Settings → Debug → Force Full Sync clears cursor

---

## 🐛 Known Issues to Ignore

- **Simulator:** "Failed to register for remote notifications" - Expected, push requires physical device
- **CoreData warnings:** SwiftData initialization messages - Safe to ignore
- **Reporter disconnected:** iOS system messages - Not app errors

---

## 🔧 Debug Tools

### Settings → Debug Section
- **Force Full Sync Now** - Clears sync cursor, removes stale actions, forces bootstrap
- Use when sync seems stuck or items not appearing

### Settings → Danger Zone
- **Delete Household Data** - Wipes all inventory, grocery, products, locations
- Server + local SwiftData both cleared
- Useful for fresh testing scenarios

### Server Commands
```bash
# Reset database completely
./server/scripts/reset-database.sh

# Check recent items
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose exec -T pantrypal-api node -e \"const db = require('./src/models/database'); const items = db.prepare('SELECT i.id, p.name, i.quantity FROM inventory i JOIN products p ON i.product_id = p.id ORDER BY i.created_at DESC LIMIT 5').all(); console.log(JSON.stringify(items, null, 2));\""

# Check sync_log
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose exec -T pantrypal-api node -e \"const db = require('./src/models/database'); const logs = db.prepare('SELECT entity_type, entity_id, action, server_timestamp FROM sync_log ORDER BY server_timestamp DESC LIMIT 10').all(); console.log(JSON.stringify(logs, null, 2));\""
```

---

## ✅ Test Completion Checklist

- [ ] Test 1: Free tier limits verified
- [ ] Test 2: Premium purchase flow works
- [ ] Test 3: Multi-device sync works with Premium
- [ ] Test 4: Free tier blocks writes for multi-user
- [ ] Test 5: Offline sync recovers correctly
- [ ] Test 6: Grocery list syncs bidirectionally
- [ ] Test 7: Locations sync to all devices
- [ ] All paywall triggers tested
- [ ] No crashes or data loss
- [ ] Sync logs show correct behavior

---

## 📱 Production Readiness

Before submitting to App Store:
1. ✅ All 7 test scenarios pass
2. ✅ Premium purchase → receipt validation works
3. ✅ Multi-device sync reliable (< 5 second latency)
4. ✅ Offline mode recovers gracefully
5. ✅ Paywall messaging clear and actionable
6. ✅ No console errors during normal operation
7. ✅ Database migrations tested (if applicable)
8. ✅ Privacy policy + terms of service available
