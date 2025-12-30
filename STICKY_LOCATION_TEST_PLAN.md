# Sticky Last Used Location - Test Plan

## Feature Overview
The app now remembers the last location a user selected and uses it as the default for both barcode scanning and adding custom items.

## Test Scenarios

### ✅ Test 1: Basic Persistence
**Steps:**
1. Open app → Scan barcode
2. Select "Fridge" as location
3. Add item
4. Close scanner
5. Open "Add Custom Item"

**Expected:**
- "Fridge" is pre-selected in Add Custom Item

**Actual:**
- [ ] Pass / [ ] Fail

---

### ✅ Test 2: Cross-Flow Persistence
**Steps:**
1. Open "Add Custom Item"
2. Select "Freezer" as location
3. Add item
4. Open "Scan Barcode"

**Expected:**
- "Freezer" is pre-selected in Scanner

**Actual:**
- [ ] Pass / [ ] Fail

---

### ✅ Test 3: Persists Across App Launches
**Steps:**
1. Select "Pantry" in scanner
2. Force quit app
3. Reopen app
4. Open scanner

**Expected:**
- "Pantry" is still selected

**Actual:**
- [ ] Pass / [ ] Fail

---

### ✅ Test 4: Per-Household Isolation
**Setup:**
- Two test accounts in different households

**Steps:**
1. Login as User A (Household A)
2. Select "Fridge" in scanner
3. Logout → Login as User B (Household B)
4. Open scanner

**Expected:**
- User B sees default "Pantry" (NOT User A's "Fridge")

**Actual:**
- [ ] Pass / [ ] Fail

---

### ✅ Test 5: Household Switch Preserves Per-Household Choice
**Steps:**
1. In Household A: Select "Fridge"
2. Switch to Household B
3. Select "Freezer"
4. Switch back to Household A

**Expected:**
- Household A still remembers "Fridge"
- Household B remembers "Freezer"

**Actual:**
- [ ] Pass / [ ] Fail

---

### ✅ Test 6: Deleted Location Fallback
**Steps:**
1. Create custom location "Garage"
2. Select "Garage" in scanner
3. Delete "Garage" location
4. Open scanner

**Expected:**
- Falls back to "Pantry" (default)
- No crash

**Actual:**
- [ ] Pass / [ ] Fail

---

### ✅ Test 7: First Time User (No Saved Location)
**Steps:**
1. Fresh install OR clear UserDefaults
2. Open scanner

**Expected:**
- Defaults to "Pantry"

**Actual:**
- [ ] Pass / [ ] Fail

---

## Technical Validation

### Code Verification
- [x] LastUsedLocationStore created
- [x] Per-household key format: `lastUsedLocation_<householdId>`
- [x] ScannerSheet uses store
- [x] AddCustomItemView uses store
- [x] onChange handlers persist selection
- [x] getSafeDefaultLocation() validates existence
- [x] Falls back to Pantry if location deleted

### Edge Cases Handled
- [x] No household (returns nil, falls back safely)
- [x] Empty locations list (returns default)
- [x] Location deleted (validates and falls back)
- [x] Household switch (different keys per household)

---

## Performance Notes
- UserDefaults write is synchronous but fast (~1ms)
- No network calls involved (local-only feature)
- Minimal memory footprint (singleton pattern)

---

## Known Limitations (v1)
- Not synced across devices (local only)
- No server-side persistence
- No "reset to default" UI option

---

## Future Enhancements (Post-MVP)
- Sync last location across user's devices
- "Reset preferences" button in Settings
- Per-item-type location memory (e.g., always put milk in Fridge)
