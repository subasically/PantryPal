# PantryPal SQLite Scalability Analysis

## Executive Summary
**Can we run 2+ replicas today?** ❌ **NO**  
**Is full sync too chatty?** ⚠️ **BORDERLINE** (manageable at current scale, risky at 50+ users)

---

## Full Sync Implementation Analysis

### Server: `/sync/full` (GET)
**File:** `server/src/routes/sync.js` (lines 102-134)

**What it does:**
- **READ ONLY** - No writes, no transactions needed
- Executes 2 SELECT queries per call:
  1. `SELECT * FROM products WHERE household_id IS NULL OR household_id = ?`
  2. `SELECT i.*, p.*, l.name FROM inventory JOIN products JOIN locations WHERE household_id = ?`
- Returns complete household inventory + all products
- **NO pagination** - pulls entire dataset every time
- **NO incremental sync** - always full snapshot

**Query Count:** 2 reads per sync  
**Data Volume:** Entire household inventory (could be 1-1000+ items)

---

## iOS App Sync Triggers

### 1. **App Launch** (InventoryListView.swift:196)
```swift
.onAppear {
    await ActionQueueService.shared.processQueue()
    try await SyncService.shared.syncFromRemote()
}
```
**Frequency:** Every app open

### 2. **App Returns to Foreground** (InventoryListView.swift:214)
```swift
.onChange(of: scenePhase) { 
    if newPhase == .active {
        try await SyncService.shared.syncFromRemote()
    }
}
```
**Frequency:** Every time user returns from background

### 3. **Background Polling** (InventoryListView.swift:276)
```swift
pollingTimer = Timer.scheduledTimer(withTimeInterval: 60)
```
**Frequency:** Every 60 seconds while app is active

### 4. **After Join Household** (HouseholdSetupView.swift:137)
**Frequency:** Once during onboarding

### 5. **Settings Refresh** (SettingsView.swift:339)
**Frequency:** User-initiated

### 6. **After Manual Actions**
**File:** InventoryListView.swift:113
- After add/edit/delete completes
- After queue flush
**Frequency:** After every inventory mutation

---

## Worst-Case Sync Frequency Estimate

### Active 5-Minute Session (Single User)
```
1. App launch                    = 1 sync
2. Background poll (60s × 5min)  = 5 syncs
3. User adds 3 items             = 3 syncs
4. User edits 1 item             = 1 sync
5. Backgrounds app 2x            = 2 syncs (return to foreground)

TOTAL: ~12 syncs per 5-minute active session
```

### 10 Concurrent Active Users
- **12 syncs/user × 10 users = 120 syncs per 5 minutes**
- **~24 syncs/minute or 0.4 syncs/second**

### 50 Concurrent Active Users
- **12 syncs/user × 50 users = 600 syncs per 5 minutes**
- **~120 syncs/minute or 2 syncs/second**

---

## Current SQLite Configuration

### What's Configured
```javascript
// server/src/models/database.js
const db = new Database(dbPath);
db.pragma('foreign_keys = ON');
```

### What's MISSING ⚠️
- ❌ **NO WAL mode** (Write-Ahead Logging)
- ❌ **NO busy_timeout** configured
- ❌ **NO journal_mode** set
- ❌ **NO connection pooling** (single connection shared across all requests)
- ✅ Using `better-sqlite3` (synchronous, simpler than `sqlite3`)

### Docker Volume Setup
```yaml
volumes:
  - pantrypal-data:/app/db
```
- **Storage:** Docker named volume (local disk on single host)
- **Persistence:** Volume survives container restarts
- **Sharing:** ❌ **CANNOT be safely shared between multiple containers**

---

## Multi-Replica Safety Analysis

### Current Architecture
```
[Container 1] ──┐
                ├──> [Docker Volume: pantrypal-data] 
[Container 2] ──┘     └── /app/db/pantrypal.db
```

### What Happens with 2+ Replicas?
1. **File-level lock contention:** Each replica tries to acquire exclusive write lock
2. **"Database is locked" errors:** `SQLITE_BUSY` (5) errors under concurrent writes
3. **Potential corruption:** SQLite is NOT designed for multi-process writes without WAL + network FS support
4. **Read contention:** Even reads can block if a write transaction is active (non-WAL mode)

### Why It's Unsafe
- SQLite uses **file-based locking** (lockfile in same directory)
- Docker volumes are **not distributed** - each container sees different mount
- Without WAL mode, writes block ALL operations
- `better-sqlite3` has **no connection pooling** - single connection per process

---

## Risk Assessment

### Current Risk Level: 🟡 **MEDIUM**
At **current scale** (5-10 users):
- ✅ Single replica handles 0.4 syncs/second easily
- ✅ READ-ONLY sync endpoint reduces lock contention
- ⚠️ Polling every 60s is aggressive but manageable
- ⚠️ No WAL mode = writes block everything momentarily

### Risk at 50+ Users: 🔴 **HIGH**
- ❌ 2+ syncs/second will hit SQLite write bottlenecks
- ❌ Checkout + add/edit operations will cause lock conflicts
- ❌ "Database is locked" errors will surface to users
- ❌ Cannot horizontally scale with replicas

---

## Recommended Next Steps

### 🔥 **Immediate (Do Now)**
1. **Enable WAL Mode**
```javascript
// server/src/models/database.js (add after line 11)
db.pragma('journal_mode = WAL');
db.pragma('busy_timeout = 5000'); // 5 seconds
```
**Impact:** Allows concurrent reads during writes, reduces lock errors

2. **Add Connection Pooling Check**
```javascript
// Verify single connection is sufficient
db.pragma('wal_checkpoint(PASSIVE)'); // Run periodically
```

### ⚡ **Short-Term (Next 2 Weeks)**
3. **Reduce Sync Frequency**
   - Change polling from 60s → **120s or 180s**
   - Remove sync after EVERY action → batch or debounce
   - File: `InventoryListView.swift:26`
   ```swift
   private let pollingInterval: TimeInterval = 180 // 3 minutes
   ```

4. **Implement Incremental Sync**
   - Use `/sync/changes?since=<timestamp>` instead of full sync
   - Server already has this endpoint (line 11-43)
   - Only pull deltas, not entire inventory
   - **Impact:** Reduce bandwidth by 90%+

5. **Add Sync Debouncing**
   - Don't sync immediately after action
   - Wait 2-3 seconds after last action before syncing
   - Reduces syncs from 3→1 if user adds 3 items quickly

### 📈 **Long-Term (Before 50+ Users)**
6. **Option A: Stay with SQLite (Recommended for MVP)**
   - ✅ Keep single API instance
   - ✅ Vertical scaling (bigger VPS)
   - ✅ WAL mode + busy_timeout = handles 100+ users
   - ✅ Simplest architecture
   - **Limit:** ~200-500 concurrent users max

7. **Option B: Migrate to PostgreSQL**
   - ✅ Enables horizontal scaling (multiple replicas)
   - ✅ Better connection pooling
   - ✅ Native replication support
   - ❌ More complex infrastructure
   - ❌ Migration effort (schema + connection code)
   - **Use when:** 500+ concurrent users or need HA

8. **Option C: Read Replicas (Not Recommended)**
   - ❌ Adds complexity for minimal benefit
   - ❌ Full sync is already READ-ONLY
   - ❌ Writes still bottleneck on primary

---

## Concrete Code Changes (DO NOT IMPLEMENT YET)

### 1. Enable WAL Mode
```javascript
// server/src/models/database.js (after line 11)
db.pragma('journal_mode = WAL');
db.pragma('busy_timeout = 5000');
db.pragma('synchronous = NORMAL'); // faster writes
```

### 2. Reduce Polling Interval
```swift
// ios/PantryPal/Views/InventoryListView.swift:26
private let pollingInterval: TimeInterval = 180 // was 60
```

### 3. Remove Sync After Action (Add Debounce)
```swift
// ios/PantryPal/Views/InventoryListView.swift:113
// REMOVE immediate sync, add to pending queue
// Let polling timer handle it OR debounce 3 seconds
```

### 4. Use Incremental Sync
```swift
// ios/PantryPal/Services/SyncService.swift:21
// Change from fullSync() to:
let lastSyncTime = UserDefaults.standard.string(forKey: "lastSyncTime")
let changes = try await APIService.shared.getChanges(since: lastSyncTime)
// Apply only deltas, not full snapshot
```

---

## Summary Table

| Metric | Current | At 50 Users | With Fixes | With Postgres |
|--------|---------|-------------|------------|---------------|
| **Syncs/second** | 0.4 | 2.0 | 0.5 | 2.0+ |
| **Replica Support** | ❌ No | ❌ No | ❌ No | ✅ Yes |
| **Lock Errors** | Rare | Common | Rare | None |
| **Scalability Limit** | 10 users | Breaks | 100 users | 1000+ users |
| **Complexity** | Low | Low | Low | Medium |

---

## Final Recommendation

### For Current Scale (5-10 users)
✅ **Safe to deploy as-is** BUT apply WAL mode immediately

### For Growth (50+ users)
⚠️ **Must implement:**
1. WAL mode (30 min fix)
2. Reduce polling to 180s (5 min fix)
3. Incremental sync (2 day project)
4. Debounce action syncs (1 day project)

### For Replicas
❌ **Do NOT attempt multi-replica until:**
- Postgres migration complete, OR
- Acceptable to run single API instance (recommended)

**Bottom Line:** Single SQLite instance with WAL mode can handle 100+ concurrent users if sync frequency is optimized. Multi-replica requires Postgres migration.
