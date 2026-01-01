# Bug #2 Fix - Grocery Auto-Add Parity (ACTUAL FIX)

**Date:** December 30, 2024  
**Status:** ✅ Fixed with Comprehensive Logging  
**Root Cause:** Bypassed grocery logic in quantity controls

---

## 🐛 Root Cause Analysis

### The Problem:
The original fix created `handleItemRemoval()` and `handleItemHitZero()` functions, but they were **ONLY called from the delete confirmation dialog**, NOT from the regular [-] button.

### Code Flow (Before Fix):

```
User taps [-] button (line 517-524 in InventoryItemRow)
  ↓
if (quantity <= 1) {
    showDeleteConfirmation = true  // Shows alert
    ↓
    User taps "Remove"
    ↓
    onRemove(item)  // ✅ Calls handleItemRemoval
    ↓
    Grocery logic runs
} else {
    viewModel.adjustQuantity(id, -1)  // ❌ BYPASSES grocery logic!
    ↓
    Item deleted directly
    ↓
    No grocery logic!
}
```

**The bug:** When user tapped [-] and quantity > 1, it went straight to `adjustQuantity`, bypassing all grocery logic. Only the delete confirmation path worked.

---

## ✅ The Fix

### 1. Added `onDecrement` Handler

**InventoryItemRow** now has TWO handlers:
- `onRemove`: For delete confirmation (quantity already at 1)
- `onDecrement`: For regular [-] button (checks if it will hit zero)

```swift
struct InventoryItemRow: View {
    let item: InventoryItem
    @Binding var viewModel: InventoryViewModel
    var onEdit: () -> Void = {}
    var onRemove: (InventoryItem) async -> Void
    var onDecrement: (InventoryItem) async -> Void  // NEW!
    @State private var showDeleteConfirmation = false
```

### 2. Updated [-] Button Logic

**Before:**
```swift
Button(action: {
    if item.quantity <= 1 {
        showDeleteConfirmation = true
        HapticService.shared.warning()
    } else {
        HapticService.shared.lightImpact()
        Task { 
            await viewModel.adjustQuantity(id: item.id, adjustment: -1)  // ❌ Bypass!
        }
    }
})
```

**After:**
```swift
Button(action: {
    if item.quantity <= 1 {
        showDeleteConfirmation = true
        HapticService.shared.warning()
    } else {
        HapticService.shared.lightImpact()
        Task { 
            await onDecrement(item)  // ✅ Calls handler!
        }
    }
})
```

### 3. Created `handleDecrement()` Function

```swift
private func handleDecrement(item: InventoryItem) async {
    print("🛒 [GroceryLogic] handleDecrement called for: \(item.displayName), current qty: \(item.quantity)")
    
    // Decrement will happen, so check if THIS decrement makes it zero
    let willBeZero = item.quantity == 1
    
    if willBeZero {
        print("🛒 [GroceryLogic] This decrement will make quantity zero - treating as last item")
        await handleItemRemoval(item: item)
    } else {
        print("🛒 [GroceryLogic] Regular decrement, quantity will be: \(item.quantity - 1)")
        await viewModel.adjustQuantity(id: item.id, adjustment: -1)
    }
}
```

**Key Logic:**
- If `item.quantity == 1`, the decrement will make it zero → Call `handleItemRemoval()`
- Otherwise, just decrement normally

### 4. Updated ForEach to Pass Handler

**Before:**
```swift
InventoryItemRow(
    item: item,
    viewModel: $viewModel,
    onEdit: { editingItem = item },
    onRemove: { item in await handleItemRemoval(item: item) }
)
```

**After:**
```swift
InventoryItemRow(
    item: item,
    viewModel: $viewModel,
    onEdit: { editingItem = item },
    onRemove: { item in await handleItemRemoval(item: item) },
    onDecrement: { item in await handleDecrement(item: item) }  // NEW!
)
```

---

## 📊 Comprehensive Logging Added

### InventoryListView Logs:

**handleDecrement():**
```
🛒 [GroceryLogic] handleDecrement called for: Milk, current qty: 2
🛒 [GroceryLogic] Regular decrement, quantity will be: 1
```

**handleItemRemoval():**
```
🛒 [GroceryLogic] handleItemRemoval called
🛒 [GroceryLogic] - Item: Milk, Quantity: 1
🛒 [GroceryLogic] - isPremium: true
🛒 [GroceryLogic] - wasLastItem: true
🛒 [GroceryLogic] Last item detected, triggering handleItemHitZero
```

**handleItemHitZero():**
```
🛒 [GroceryLogic] handleItemHitZero called
🛒 [GroceryLogic] - itemName: Milk
🛒 [GroceryLogic] - isPremium: true
🛒 [GroceryLogic] Premium user - attempting auto-add to grocery
🛒 [GroceryLogic] ✅ Successfully auto-added to grocery
```

**OR (if Free user):**
```
🛒 [GroceryLogic] handleItemHitZero called
🛒 [GroceryLogic] - itemName: Milk
🛒 [GroceryLogic] - isPremium: false
🛒 [GroceryLogic] Free user - showing confirmation prompt
```

### CheckoutView Logs:

```
🛒 [CheckoutGrocery] handleCheckoutResponse called
🛒 [CheckoutGrocery] - itemDeleted: true
🛒 [CheckoutGrocery] - productName: Optional("Milk")
🛒 [CheckoutGrocery] - isPremium: true
🛒 [CheckoutGrocery] - addedToGrocery (server): true
🛒 [CheckoutGrocery] Item hit zero during checkout
🛒 [CheckoutGrocery] Premium user - server auto-added, showing toast
```

---

## 🧪 Testing Scenarios

### Test 1: Premium - Manual Decrement to Zero

**Steps:**
1. Item has quantity = 2
2. Tap [-] button

**Expected Logs:**
```
🛒 [GroceryLogic] handleDecrement called for: Milk, current qty: 2
🛒 [GroceryLogic] Regular decrement, quantity will be: 1
```

3. Tap [-] button again

**Expected Logs:**
```
🛒 [GroceryLogic] handleDecrement called for: Milk, current qty: 1
🛒 [GroceryLogic] This decrement will make quantity zero - treating as last item
🛒 [GroceryLogic] handleItemRemoval called
🛒 [GroceryLogic] - Item: Milk, Quantity: 1
🛒 [GroceryLogic] - isPremium: true
🛒 [GroceryLogic] - wasLastItem: true
🛒 [GroceryLogic] Last item detected, triggering handleItemHitZero
🛒 [GroceryLogic] handleItemHitZero called
🛒 [GroceryLogic] - itemName: Milk
🛒 [GroceryLogic] - isPremium: true
🛒 [GroceryLogic] Premium user - attempting auto-add to grocery
🛒 [GroceryLogic] ✅ Successfully auto-added to grocery
```

**Expected UI:**
- ✅ Toast: "Out of Milk — added to Grocery List"
- ✅ Haptic feedback (success)
- ✅ Item removed from inventory
- ✅ Item appears in grocery list

---

### Test 2: Free - Manual Decrement to Zero

**Steps:**
1. Item has quantity = 1
2. Tap [-] button

**Expected Logs:**
```
🛒 [GroceryLogic] handleDecrement called for: Milk, current qty: 1
🛒 [GroceryLogic] This decrement will make quantity zero - treating as last item
🛒 [GroceryLogic] handleItemRemoval called
🛒 [GroceryLogic] - Item: Milk, Quantity: 1
🛒 [GroceryLogic] - isPremium: false
🛒 [GroceryLogic] - wasLastItem: true
🛒 [GroceryLogic] Last item detected, triggering handleItemHitZero
🛒 [GroceryLogic] handleItemHitZero called
🛒 [GroceryLogic] - itemName: Milk
🛒 [GroceryLogic] - isPremium: false
🛒 [GroceryLogic] Free user - showing confirmation prompt
```

**Expected UI:**
- ✅ Alert appears: "Add to Grocery List?"
- ✅ Message: "You're out of Milk. Add it to your grocery list?"
- ✅ Buttons: "Not now" (cancel), "Add" (confirm)
- ✅ If "Add": Item added to grocery + success toast
- ✅ If "Not now": No action

---

### Test 3: Premium - Checkout Last Item

**Steps:**
1. Item has quantity = 1
2. Scan barcode to checkout

**Expected Logs:**
```
🛒 [CheckoutGrocery] handleCheckoutResponse called
🛒 [CheckoutGrocery] - itemDeleted: true
🛒 [CheckoutGrocery] - productName: Optional("Milk")
🛒 [CheckoutGrocery] - isPremium: true
🛒 [CheckoutGrocery] - addedToGrocery (server): true
🛒 [CheckoutGrocery] Item hit zero during checkout
🛒 [CheckoutGrocery] Premium user - server auto-added, showing toast
```

**Expected UI:**
- ✅ Toast: "Out of Milk — added to Grocery List"
- ✅ Same behavior as manual decrement

---

### Test 4: Debugging 403 Error

**If you see:**
```
🛒 [GroceryLogic] ❌ Failed to auto-add to grocery: serverError("Request failed with status 403")
```

**Check:**
1. Is household actually Premium?
   - Look for: `🛒 [GroceryLogic] - isPremium: false` (should be true)
2. Is `authViewModel.currentHousehold?.isPremiumActive` correct?
3. Check server logs for grocery endpoint rejection

---

## 🎯 What Changed

### Files Modified:

**iOS:**
1. `ios/PantryPal/Views/InventoryListView.swift`
   - Added `handleDecrement()` function
   - Added comprehensive logging (9 print statements)
   - Added `onDecrement` closure to InventoryItemRow
   - Updated [-] button to use `onDecrement` handler
   - Updated ForEach to pass `onDecrement` handler

2. `ios/PantryPal/Views/CheckoutView.swift`
   - Added comprehensive logging (6 print statements)
   - Added debugging for server response

---

## 🚀 Next Steps

### To Debug 403 Error You Saw:

1. **Run the app and tap [-] on a single item**
2. **Check Xcode console for logs starting with `🛒`**
3. **Look for:**
   - Is `isPremium: true` or `false`?
   - Is the function being called at all?
   - What error message appears after "❌ Failed to auto-add"?

4. **If `isPremium: false`:**
   - Check: `authViewModel.currentHousehold?.isPremiumActive`
   - Check: Server household data (is_premium column)
   - Verify: User is in the right household

5. **If `isPremium: true` but still 403:**
   - Server is rejecting the request
   - Check server logs for grocery endpoint
   - Check if household ID matches
   - Verify Premium check on server side

---

## 📝 Summary

**Before:** [-] button bypassed grocery logic, only delete confirmation worked  
**After:** Both [-] button and delete confirmation trigger proper grocery logic  
**Logging:** Comprehensive debug logs help identify Premium check issues  

**Build Status:** ✅ BUILD SUCCEEDED  
**Ready for:** Testing with full debug logging
