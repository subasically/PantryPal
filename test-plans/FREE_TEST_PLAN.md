# Free Tier Manual Test Plan

## Setup
- [ ] 1) Use an iPhone with camera. Optional: enable Face ID or Touch ID.
- [ ] 2) Install the build and confirm it can reach the API at https://api-pantrypal.subasically.me.
- [ ] 3) Prepare two Free accounts (examples): free-owner@example.com / Password123! and free-member@example.com / Password123!.
- [ ] 4) Example locations to use: Pantry, Fridge, Freezer (default).
- [ ] 5) Example UPCs to use: 123456789012 (Test Product), 999888777666 (Custom Product With UPC), 123456789999 (Checkout Test Product), 000000000000 (not found).
- [ ] 6) Example items to use: Test Product (Test Brand), Homemade Jam (Family Recipe), Milk.

## Preconditions
- [ ] 1) Log in as the Free Owner and verify Settings does NOT show the Premium badge.
- [ ] 2) Confirm default locations exist (Pantry/Fridge/Freezer).
- [ ] 3) Optional: clear existing inventory and grocery items to start from empty.
- [ ] 4) Turn OFF app lock unless a test step enables it.

## Test Cases

### Auth and Onboarding (Free vs Premium)
- [ ] 1) Sign in with Apple and complete auth. Expected: app lands in Household Setup or main tabs; account created and logged in.
- [ ] 2) Sign out, then log in with email and password. Expected: login succeeds and a biometric enable prompt appears if available.
- [ ] 3) Accept the biometric prompt. Expected: next time the Login screen shows a "Sign in with Face ID/Touch ID" button.
- [ ] 4) Force quit and relaunch the app. Expected: session persists and user returns to main tabs (unless app lock is enabled).
- [ ] 5) Free vs Premium: authentication, session persistence, and sign-out behavior are the same.

### App Lock (Free vs Premium)
- [ ] 1) Settings -> Security: enable "Require Face ID/Touch ID to Open". Expected: toggle stays on.
- [ ] 2) Background the app for <30 seconds, then return. Expected: app opens without lock overlay.
- [ ] 3) Background the app for >30 seconds, then return. Expected: lock overlay appears and biometric unlock is required.
- [ ] 4) Force quit and relaunch with app lock enabled. Expected: lock overlay appears on cold launch.
- [ ] 5) Free vs Premium: app lock behavior is identical.

### Household (Free vs Premium)
- [ ] 1) New user flow: tap "Create my household". Expected: household is created and main tabs appear.
- [ ] 2) Join via invite code: open Settings -> Household Sharing -> Join Another Household -> enter a valid 6-character code. Expected: validation shows household name and member count.
- [ ] 3) Join via QR: tap "Scan QR Code" and scan the invite QR. Expected: code auto-fills and validates.
- [ ] 4) Switch household: if already in a household, tap "Switch Household" and confirm. Expected: confirmation message appears and local inventory is replaced after sync.
- [ ] 5) Free vs Premium: joining a household works for both; generating invites is Premium-gated.

### Inventory Core (Free vs Premium)
- [ ] 1) Add custom item: tap +, enter "Homemade Jam" / "Family Recipe", set Location = Pantry, Qty = 2, set expiration in 5 days, Save. Expected: item appears with correct location and expiration.
- [ ] 2) Edit item: tap the item, change quantity to 3, change location to Fridge, set expiration to yesterday. Expected: list shows updated quantity, location, and expired status.
- [ ] 3) Search: search "Jam", then search by brand "Family" and by UPC "999888777666". Expected: matching items filter correctly.
- [ ] 4) Filter: switch to Expiring Soon and Expired. Expected: items move between filters based on expiration dates.
- [ ] 5) Delete: swipe to delete an item and confirm. Expected: item is removed from list.
- [ ] 6) Location required: try to save a custom item with no location (if no locations exist). Expected: Save is disabled and a location-required message is shown.
- [ ] 7) Sticky location: add an item with Location = Freezer, then open Add Custom Item again. Expected: Freezer is preselected as the default.
- [ ] 8) Free vs Premium: core inventory add/edit/delete/search works the same; only limits differ.

### Barcode Scan and Custom UPC (Free vs Premium)
- [ ] 1) Scan UPC 000000000000. Expected: app shows "New Item" flow and prompts for name/brand.
- [ ] 2) Scan UPC 123456789012 after creating Test Product. Expected: quick add succeeds and quantity increases if the item already exists.
- [ ] 3) Scan UPC 999888777666 after creating "Custom Product With UPC". Expected: item is found and added without requiring a new custom entry.
- [ ] 4) Free vs Premium: scan and custom product flows are the same.

### Empty State and Pull-to-Refresh (Free vs Premium)
- [ ] 1) Delete all items. Expected: empty state shows "No items in your pantry" and Scan/Add buttons.
- [ ] 2) Pull to refresh on empty state. Expected: sync runs and list refreshes without errors.
- [ ] 3) Free vs Premium: empty state and refresh behavior are the same.

### Checkout (Free vs Premium)
- [ ] 1) Scan UPC 123456789999 for "Checkout Test Product" with quantity >=2. Expected: quantity decrements by 1 and success card shows previous -> new quantity.
- [ ] 2) Continue scanning until quantity hits 0. Expected: item is removed and an "Add to Grocery List?" prompt appears.
- [ ] 3) Open history (clock icon). Expected: history shows entries with correct product name, no duplicates, and no "undefined" user names (shows "by You" or "by Household member").
- [ ] 4) Free vs Premium: checkout scanning works the same; Premium may also auto-add to grocery (see Grocery tests).

### Grocery List (Free vs Premium)
- [ ] 1) Manual add: open Grocery tab, tap +, add "Milk". Expected: item appears in list.
- [ ] 2) Manual remove: swipe to delete "Milk". Expected: item is removed.
- [ ] 3) Brand display: if any grocery item includes a brand, it should display as "Brand - Name"; if no brand, only the name is shown.
- [ ] 4) Matching rules (UPC first): add grocery item for "Test Product" and restock via scan UPC 123456789012. Expected: grocery item is removed by UPC match.
- [ ] 5) Matching rules (name fallback): add grocery item named "Milk" and restock via custom add named "Milk" (no UPC). Expected: grocery item is removed by normalized name match.
- [ ] 6) Free vs Premium: Free uses manual add/remove and sees prompts on zero; Premium should auto-add on zero and auto-remove on restock.

### Paywall and Limits (Free vs Premium)
- [ ] 1) Add items until the free limit (default 25) is reached. Expected: adding the next item triggers the paywall and the add is blocked.
- [ ] 2) While over limit, delete or reduce items. Expected: deletions succeed and count decreases.
- [ ] 3) Grocery limit: add grocery items up to the free limit and try one more. Expected: error "Grocery list limit reached" and no new item added.
- [ ] 4) Household Sharing: open Settings -> Household Sharing and try to generate an invite. Expected: lock message and paywall prompt.
- [ ] 5) Free vs Premium: Premium removes limits and unlocks invite generation.

### Sync and Multi-Device Sanity (Free vs Premium)
- [ ] 1) Add or edit an item and then pull to refresh. Expected: change persists after refresh.
- [ ] 2) Background and re-open the app. Expected: auto-sync runs and list updates.
- [ ] 3) Free vs Premium: sync timing behavior is the same.

### Toasts (Free vs Premium)
- [ ] 1) Trigger a success toast by adding an item. Expected: toast slides down from top, green styling, haptic feedback.
- [ ] 2) Trigger an error toast by failing a request (e.g., add beyond limit). Expected: red/orange toast, longer display duration.
- [ ] 3) Trigger an info toast (e.g., grocery auto-remove). Expected: purple/blue styling and no haptic.
- [ ] 4) Trigger multiple toasts quickly. Expected: toasts queue in order and dismiss automatically.
- [ ] 5) Free vs Premium: toast behavior is the same.

## Expected Results
- [ ] 1) Free users can add up to the limit, and are blocked with a paywall at the limit.
- [ ] 2) Inventory requires a valid location for all items.
- [ ] 3) Checkout decrements quantity and logs history without duplicates or "undefined" names.
- [ ] 4) Grocery list supports manual add/remove; auto-add is not guaranteed for Free.
- [ ] 5) App lock enforces biometric unlock after 30+ seconds in background.

## Notes
- [ ] 1) Biometric login enable toggle only appears for password-based accounts, not Apple sign-in.
- [ ] 2) Auto-add/auto-remove grocery behavior is primarily server-side; the app also shows an add prompt on zero.
- [ ] 3) If a grocery item has no brand, the list shows only the name.

## Risks / Verify
- [ ] 1) Smart Scanner toggle is stored in preferences but has no visible Settings UI; verify default behavior uses standard scanner.
- [ ] 2) Paywall triggers via NotificationCenter; verify it appears when triggered from Grocery tab and Household Sharing.
- [ ] 3) Auto-remove on restock is only called in add/scan flows, not when using the + button on existing items.
- [ ] 4) Household "leave" flow is not present; switching households is the only in-app path.

## Print Checklist
- [ ] 1) Sign in (email + Apple), session persists, and sign out works.
- [ ] 2) Add/scan/edit/delete inventory items with required locations.
- [ ] 3) Checkout an item to zero and confirm grocery prompt behavior.
- [ ] 4) Grocery manual add/remove works and list displays correctly.
- [ ] 5) Free limits enforce paywall and block adds beyond limits.
