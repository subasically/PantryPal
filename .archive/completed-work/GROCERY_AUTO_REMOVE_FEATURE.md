# Grocery Auto-Remove on Restock Feature

**Date:** 2025-12-30
**Status:** ✅ Implemented

## Overview
Automatically removes items from the grocery list when they are restocked in inventory, creating a seamless shopping-to-pantry workflow.

## Features Implemented

### 1. Grocery Items Now Store Brand + UPC
- **Schema Changes:**
  - Added `brand TEXT` and `upc TEXT` columns to `grocery_items` table
  - Added index on `upc` for fast lookups
  - Migration added to `database.js`

- **API Changes:**
  - `POST /api/grocery` now accepts optional `brand` and `upc` fields
  - `GET /api/grocery` returns `brand` and `upc` in response

### 2. New Server Endpoints for Auto-Remove
- **`DELETE /api/grocery/by-upc/:upc`**
  - Removes grocery item matching the UPC
  - Returns `{ success: true, removed: bool, count: int }`
  - Idempotent (200 even if nothing removed)

- **`DELETE /api/grocery/by-name/:normalizedName`**
  - Removes grocery item by normalized name (fallback when no UPC)
  - Normalized: lowercase, trimmed, collapsed whitespace
  - Returns `{ success: true, removed: bool, count: int }`

### 3. iOS Changes

#### Models Updated
- **`GroceryItem`**: Added `brand`, `upc`, `displayName` computed property
- **`SDGroceryItem`**: Added `brand` and `upc` fields for local cache
- **`APIService`**: 
  - `addGroceryItem()` now accepts optional brand/upc
  - Added `removeGroceryItemByUPC()` and `removeGroceryItemByName()`

#### GroceryViewModel
- Added `attemptAutoRemove(upc:name:brand:)` method
  - Priority 1: Try UPC match (most accurate)
  - Priority 2: Fallback to normalized name match
  - Logs all attempts for debugging
  - Refreshes list on successful removal

#### InventoryListView
- Added `groceryViewModel` instance
- Added helper functions:
  - `attemptGroceryAutoRemove(forItem:)` - remove by item data
  - `tryAutoRemoveFromGrocery(name:upc:)` - remove by name/upc
  - `checkRecentlyAddedForGroceryRemoval()` - fallback for scanner
- Hooked into:
  - SmartScannerView callback (after successful add)
  - AddCustomItemView callback (after successful add)
  - ScannerSheet callback (after successful add)

#### UI Improvements
- **GroceryListView**: Now displays `brand – name` when brand exists
- **Toast Notifications**: Shows "Removed X from grocery list" on auto-remove

## Matching Logic

### Priority 1: UPC Match (Preferred)
```
IF grocery_item.upc EXISTS AND inventory_item.upc == grocery_item.upc
  → Remove grocery item
```

### Priority 2: Name Match (Fallback)
```
IF no UPC match:
  normalized_grocery_name = lowercase(trim(grocery_item.name))
  normalized_inventory_name = lowercase(trim(inventory_item.name))
  IF normalized_grocery_name == normalized_inventory_name
    → Remove grocery item
```

## Auto-Remove Triggers

Grocery items are automatically removed when:

1. **Barcode Scan Add** - Item scanned and added to inventory
2. **Custom Item Add** - Custom item created with quantity > 0
3. **Quantity Edit** - Inventory item quantity increased from 0 to >0
4. **Quick Add** - Any quick-add action that results in inventory quantity > 0

## User Experience

### Before (Manual Workflow)
1. Run out of "Barilla Spaghetti"
2. Add "Spaghetti" to grocery list manually
3. Buy spaghetti at store
4. Scan barcode to add to pantry
5. **PROBLEM:** "Spaghetti" still shows on grocery list
6. Manually remove from grocery list

### After (Automated Workflow)
1. Run out of "Barilla Spaghetti"
2. Add to grocery list (manual or auto-add Premium feature)
3. Buy spaghetti at store
4. Scan barcode to add to pantry
5. ✅ **AUTOMATIC:** Grocery list item removed instantly
6. 🎉 **BONUS:** Toast shows "Removed Barilla Spaghetti from grocery list"

## Testing Checklist

- [x] Add item to grocery list with UPC, restock with same UPC → Auto-removed
- [x] Add item to grocery list name-only, restock with matching name → Auto-removed
- [x] Add item to grocery list with UPC-A, restock with UPC-B → NOT removed (correct)
- [x] Grocery list displays brand + name when available
- [x] Toast appears on auto-remove
- [x] Server migration applies cleanly
- [x] No duplicate removals on rapid restocking

## Database Migration

The migration runs automatically on server start:

```sql
ALTER TABLE grocery_items ADD COLUMN brand TEXT;
ALTER TABLE grocery_items ADD COLUMN upc TEXT;
CREATE INDEX IF NOT EXISTS idx_grocery_items_upc ON grocery_items(upc);
```

## Deployment

### Server
```bash
ssh root@62.146.177.62
cd /root/pantrypal-server
# Copy updated files: database.js, grocery.js, schema.sql
docker-compose up -d --build --force-recreate
docker-compose logs -f
```

### iOS
- Build and deploy v1.3.0+
- Migration is client-side via SwiftData schema updates

## Future Enhancements (Post-MVP)

- [ ] Configurable auto-remove setting (allow users to opt-out)
- [ ] Confirmation prompt before auto-remove (optional)
- [ ] Smart matching using fuzzy search (e.g., "Eggs" matches "Large Eggs")
- [ ] Batch auto-remove on inventory sync
- [ ] Analytics on auto-remove success rate

## Notes

- Auto-remove is **silent** (only toast notification)
- Works for **all users** (Free + Premium)
- UPC matching is **exact** (no fuzzy logic)
- Name matching uses **normalized strings** (case-insensitive, whitespace-collapsed)
- Idempotent: Safe to call multiple times
- Server-authoritative: All removals validated server-side

---

**Related Files:**
- Server: `grocery.js`, `database.js`, `schema.sql`
- iOS: `GroceryViewModel.swift`, `InventoryListView.swift`, `GroceryListView.swift`, `APIService.swift`, `Models.swift`, `SwiftDataModels.swift`
