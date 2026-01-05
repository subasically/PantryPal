# Debug Multi-Device Sync Issues

Systematically debug sync problems between devices.

## When to Use
- "Items aren't syncing between devices"
- "Changes on one device don't appear on another"
- "Sync appears to work but nothing happens"
- After adding sync-related features

## Quick Diagnosis

### Step 1: Check Server sync_log Table
```bash
# SSH to production server
ssh root@62.146.177.62

# Check recent sync entries
cd /root/pantrypal-server
docker-compose exec pantrypal-api sqlite3 /app/db/pantrypal.db \
  "SELECT entity_type, entity_id, action, server_timestamp FROM sync_log ORDER BY server_timestamp DESC LIMIT 10;"
```

**Look for:**
- Are new entries being created when items are added?
- Are `entity_id` values UUIDs (correct) or "create"/"update"/"delete" (wrong)?
- Are `action` values "create"/"update"/"delete" (correct) or UUIDs (wrong)?

### Step 2: Check iOS Console Logs
Run the app in Xcode and watch for:

```
✅ [SyncService] Received 5 changes from server
✅ [SyncService] Applied 5 changes successfully
```

**Red flags:**
- "Received 0 changes" when you expect changes
- "Action create processed successfully" but item doesn't appear
- No sync logs at all (sync not running)

### Step 3: Force Full Sync on iOS
Settings → Debug → Force Full Sync Now

This clears:
- Sync cursor (forces bootstrap from beginning)
- Pending actions queue (removes stale operations)
- In-memory sync state

### Step 4: Verify Household Setup
Common issue: User has `household_id = NULL`

**Check:**
```bash
# On server
docker-compose exec pantrypal-api sqlite3 /app/db/pantrypal.db \
  "SELECT id, email, household_id FROM users;"
```

**Fix:** User must create or join household before sync works

## Common Issues & Solutions

### Issue 1: Parameter Order Mismatch
**Symptom:** sync_log entries have entity_id = "create" and action = UUID

**Cause:** syncLogger.js called with wrong parameter order
```javascript
// WRONG (old bug)
function logSync(householdId, entityType, operation, entityId, metadata)

// Called as:
logSync(householdId, entityType, entityId, operation, metadata)
```

**Fix:** Update function signature to match call sites
```javascript
// CORRECT
function logSync(householdId, entityType, entityId, operation, metadata)
```

**Migration:** Fix corrupted entries
```javascript
const corrupted = db.prepare(`
  SELECT * FROM sync_log 
  WHERE entity_id IN ('create', 'update', 'delete')
`).all();

for (const row of corrupted) {
  db.prepare(`
    UPDATE sync_log 
    SET entity_id = ?, action = ?
    WHERE id = ?
  `).run(row.action, row.entity_id, row.id);
}
```

### Issue 2: Sync Cursor Stuck
**Symptom:** "Received 0 changes" on every sync, but sync_log has new entries

**Cause:** UserDefaults sync cursor points to timestamp after latest changes

**Fix:** Use Force Full Sync button in Settings → Debug

### Issue 3: Stale Pending Actions
**Symptom:** "Action processed successfully" but no sync_log entry created

**Cause:** Pending actions from old household or deleted items

**Fix:** 
```swift
// Delete stale pending actions
let actions = try? modelContext.fetch(FetchDescriptor<SDPendingAction>())
if let actions = actions {
    for action in actions where action.createdAt < Date().addingTimeInterval(-86400) {
        modelContext.delete(action)
    }
}
```

### Issue 4: Household Not Created
**Symptom:** "Location not found" error, can't add items

**Cause:** User dismissed HouseholdSetupView without creating household

**Fix:** Update HouseholdSetupView to call `completeHouseholdSetup()` before dismiss
```swift
Button("Create my Household") {
    Task {
        await authViewModel.completeHouseholdSetup()  // MUST call this!
        authViewModel.showHouseholdSetup = false
    }
}
```

## Testing Multi-Device Sync

### Test Setup
1. Reset database: `./server/scripts/reset-database.sh`
2. Delete apps from both devices
3. Device A: Sign in, create household, go Premium
4. Device B: Sign in with different account, join household

### Test Cases
1. **Device A adds item** → Device B should see it within seconds
2. **Device B adds item** → Device A should see it within seconds  
3. **Device A updates quantity** → Device B should see new quantity
4. **Device B deletes item** → Device A should see it removed
5. **Both devices add items simultaneously** → Both should sync bidirectionally

### What to Watch
- Console logs: "Received X changes", "Applied X changes"
- sync_log table: New entries for each operation
- Sync happens automatically every 30 seconds
- Manual sync: Pull down to refresh on inventory/grocery screens

## Debug Checklist

- [ ] sync_log entries have correct entity_id (UUID) and action (create/update/delete)
- [ ] Users have valid household_id (not NULL)
- [ ] iOS console shows "Received X changes" and "Applied X changes"
- [ ] Force Full Sync clears stuck state
- [ ] Test server running (http://localhost:3002/health)
- [ ] Multiple devices can join same household
- [ ] Items sync bidirectionally within seconds
- [ ] Offline → Online recovery works

## Reference Files
- `server/src/services/syncLogger.js` - Sync logging (parameter order critical!)
- `ios/PantryPal/Services/SyncCoordinator.swift` - Client-side sync orchestration
- `ios/PantryPal/Services/SyncService.swift` - Sync API calls
- `ios/PantryPal/Views/SettingsView.swift` - Force Full Sync button (line 180)
- `TESTING.md` - Comprehensive test plan (Test 3 = Multi-Device)

## Quick Commands

```bash
# Reset database for clean testing
./server/scripts/reset-database.sh

# Check sync logs on server
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose logs -f pantrypal-api | grep -i sync"

# Dump sync_log table
ssh root@62.146.177.62 "cd /root/pantrypal-server && docker-compose exec pantrypal-api sqlite3 /app/db/pantrypal.db 'SELECT * FROM sync_log;'"

# Force sync in iOS
# Settings → Debug → Force Full Sync Now
```
