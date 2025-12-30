# Regression Smoke Test (10-15 minutes)

## Setup
- [ ] 1) Use one device (two if testing Premium sharing) with camera and network access.
- [ ] 2) Log in to a Free household; optionally have a Premium household ready.
- [ ] 3) Ensure at least one location exists (Pantry/Fridge/Freezer).

## Preconditions
- [ ] 1) Inventory has at least 1 item and grocery list has at least 1 item.
- [ ] 2) App lock is OFF unless you are testing it specifically.

## Test Cases

### Core Free Smoke
- [ ] 1) Launch app and confirm you land on Pantry tab. Expected: list loads without errors.
- [ ] 2) Tap +, add "Milk" in Pantry, Qty 1. Expected: item appears with location.
- [ ] 3) Search for "Milk". Expected: item filters correctly.
- [ ] 4) Tap item, edit quantity to 2, Save. Expected: quantity updates.
- [ ] 5) Swipe-delete the item. Expected: item is removed.
- [ ] 6) Open Grocery tab, add "Bread" and remove it. Expected: add/remove works.
- [ ] 7) Open Checkout tab, scan a known UPC (123456789999). Expected: success card and quantity decrement.
- [ ] 8) Open Checkout History. Expected: entries show product name and "by You".
- [ ] 9) Pull to refresh on Pantry. Expected: no errors and list refreshes.

### Premium Smoke (if Premium household available)
- [ ] 1) Verify Premium badge in Settings. Expected: badge visible.
- [ ] 2) Open Household Sharing and generate invite. Expected: QR and code appear.
- [ ] 3) Add items beyond 25 in Pantry. Expected: no paywall, adds succeed.
- [ ] 4) Checkout last item to zero. Expected: grocery auto-add occurs after sync.

### App Lock Quick Check (optional)
- [ ] 1) Enable app lock and background for >30 seconds. Expected: lock overlay appears.

## Expected Results
- [ ] 1) Core add/edit/delete/checkout/grocery flows work without crashes.
- [ ] 2) Sync and refresh complete without errors.
- [ ] 3) Premium features (if enabled) are unlocked and functional.

## Notes
- [ ] 1) If any step fails, capture screen recording and note the last successful step.
- [ ] 2) For Premium auto-add, the app may still show a prompt; verify the grocery item appears after sync.

## Print Checklist
- [ ] 1) Pantry add/edit/delete works.
- [ ] 2) Grocery add/remove works.
- [ ] 3) Checkout scan and history work.
- [ ] 4) Sync/refresh works.
- [ ] 5) Premium features (if enabled) work.
