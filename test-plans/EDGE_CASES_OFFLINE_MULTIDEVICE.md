# Edge Cases: Offline + Multi-Device

## Setup
- [ ] 1) Use two devices signed into the same household (Owner + Member).
- [ ] 2) Ensure both devices have the latest app build and can reach the API.
- [ ] 3) Prepare baseline data: at least 3 inventory items and 2 grocery items.

## Preconditions
- [ ] 1) Both devices have completed an initial sync (open Pantry tab and wait for load).
- [ ] 2) App lock is OFF unless a test step enables it.

## Test Cases

### Offline Inventory Queue
- [ ] 1) Device A: enable Airplane Mode. Add "Offline Rice" with Location = Pantry. Expected: item appears locally.
- [ ] 2) Device A: edit quantity and delete the item while still offline. Expected: local list updates.
- [ ] 3) Device A: disable Airplane Mode and pull to refresh. Expected: queued actions sync without errors and server matches local state.
- [ ] 4) Free vs Premium: offline queue behavior is the same.

### Offline Barcode and Checkout
- [ ] 1) Device A offline: scan UPC 123456789012 that exists locally. Expected: quick add succeeds locally.
- [ ] 2) Device A offline: scan UPC 000000000000 (not found). Expected: error or "product not found locally" flow.
- [ ] 3) Device A offline: checkout a locally cached product by UPC. Expected: quantity decrements locally.
- [ ] 4) Device A offline: checkout a UPC not in local cache. Expected: error message about offline or not found.
- [ ] 5) Free vs Premium: offline scanning and checkout behavior is the same.

### Offline Household and Sharing
- [ ] 1) Device A offline: open Household Sharing and try to generate invite. Expected: error or failure to load.
- [ ] 2) Device A offline: try to join a household via code/QR. Expected: validation fails due to no network.
- [ ] 3) Free vs Premium: offline household operations should fail for both.

### Multi-Device Sync Sanity
- [ ] 1) Device A online: add "Sync Test Beans" in Fridge. Expected: item appears on A.
- [ ] 2) Device B: bring app to foreground. Expected: auto-sync pulls new item.
- [ ] 3) Device B: delete the item. Expected: item removed on B.
- [ ] 4) Device A: pull to refresh. Expected: item removal appears on A.
- [ ] 5) Free vs Premium: sync propagation should be the same.

### Multi-Device Conflict (Quantity)
- [ ] 1) Device A: set "Test Product" quantity to 2.
- [ ] 2) Device A (online): tap + to make quantity 3.
- [ ] 3) Device B (online, before refresh): tap - to make quantity 1.
- [ ] 4) Refresh both devices. Expected: final quantity is consistent across devices (note which change wins).
- [ ] 5) Free vs Premium: conflict behavior is the same.

### Grocery Auto-Remove Across Devices
- [ ] 1) Add grocery item "Milk" on Device A.
- [ ] 2) Restock "Milk" via custom add on Device B. Expected: grocery item is removed after sync.
- [ ] 3) Free vs Premium: Premium should auto-remove; Free may still auto-remove if triggered by add/scan flow.

### Household Premium Entitlements (Multi-Device)
- [ ] 1) Verify Premium badge on both devices if household is Premium. Expected: badge appears for all members.
- [ ] 2) Free vs Premium: in Free, member write actions on grocery list may be blocked; in Premium they should work.

### Sticky Location Per Household Per Device
- [ ] 1) Device A: set last used location to Freezer by adding an item. Expected: Freezer becomes default for future adds on A.
- [ ] 2) Device B: add an item and set location to Pantry. Expected: Pantry becomes default on B.
- [ ] 3) Expected: sticky location does NOT sync across devices; it is stored locally per device and household.

## Expected Results
- [ ] 1) Offline actions appear locally and sync correctly when back online.
- [ ] 2) Multi-device sync keeps inventory and grocery lists consistent after refresh.
- [ ] 3) Conflicts resolve deterministically (record outcome if inconsistent).

## Notes
- [ ] 1) ActionQueue stops processing on the first failing request; retry by pulling to refresh after network restores.
- [ ] 2) Checkout history is loaded from the API only; offline history may not be available.

## Print Checklist
- [ ] 1) Offline add/edit/delete syncs back correctly.
- [ ] 2) Multi-device add/delete propagates on refresh.
- [ ] 3) Offline checkout works for cached items and fails for unknown UPCs.
- [ ] 4) Premium entitlements apply on both devices (if Premium enabled).
