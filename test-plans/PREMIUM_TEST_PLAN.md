# Premium Tier Manual Test Plan

## Setup
- [ ] 1) Use two iPhones with camera (or one phone and one simulator) to test household sharing.
- [ ] 2) Install a DEBUG build if you plan to use Premium simulation (see below).
- [ ] 3) Prepare two accounts in the same household: premium-owner@example.com / Password123! and premium-member@example.com / Password123!.
- [ ] 4) Example locations to use: Pantry, Fridge, Freezer (default).
- [ ] 5) Example UPCs to use: 123456789012 (Test Product), 999888777666 (Custom Product With UPC), 123456789999 (Checkout Test Product), 000000000000 (not found).

## Preconditions
- [ ] 1) Ensure the household is Premium. If needed, use one of the DEBUG-only methods below.
- [ ] 2) Verify Settings shows the Premium badge for the owner account.
- [ ] 3) Confirm default locations exist (Pantry/Fridge/Freezer).

## Test Cases

### Premium Activation (DEBUG ONLY - not in production)
- [ ] 1) Trigger the paywall (e.g., attempt to generate an invite in Household Sharing). Expected: Paywall appears.
- [ ] 2) Tap the "Simulate Premium" button (ladybug icon). Expected: Paywall closes and Premium badge appears in Settings.
- [ ] 3) If "Simulate Premium" fails, confirm the server accepts the admin key "dev-admin-key-change-me" (DEBUG only). Expected: Premium status updates after refresh.
- [ ] 4) Free vs Premium: Paywall should be dismissible in Free, but Premium status should remove the paywall for gated actions.

### Household Sharing (Premium vs Free)
- [ ] 1) Open Settings -> Household Sharing and tap "Generate Invite Code". Expected: invite code and QR are displayed.
- [ ] 2) On the member device, join via code or QR. Expected: join succeeds and shared inventory appears after sync.
- [ ] 3) On both devices, verify Premium badge and Premium features are available. Expected: Premium is household-wide.
- [ ] 4) Free vs Premium: Free shows lock + paywall for invite generation; Premium allows invite creation.

### Inventory Limits (Premium vs Free)
- [ ] 1) Add 30+ inventory items (mix scan and custom add). Expected: no limit errors, no paywall.
- [ ] 2) Verify adding items remains enabled after 25 items. Expected: add buttons remain active.
- [ ] 3) Free vs Premium: Free blocks new adds at the limit and shows the paywall; Premium does not.

### Grocery Limits (Premium vs Free)
- [ ] 1) Add 30+ grocery items manually. Expected: no limit errors, no paywall.
- [ ] 2) With multiple household members, add/remove grocery items on both devices. Expected: writes are allowed.
- [ ] 3) Free vs Premium: Free is limited to 25 and may block writes in shared households; Premium is unlimited.

### Auto-Add to Grocery (Premium vs Free)
- [ ] 1) Set a product quantity to 1, then decrement to 0 from Inventory. Expected: grocery item appears automatically after sync.
- [ ] 2) Checkout the last item (quantity goes to 0). Expected: grocery item appears automatically after sync.
- [ ] 3) Observe the in-app prompt "Add to Grocery List?". Expected: prompt may appear, but Premium should still auto-add even if "Not now" is tapped.
- [ ] 4) Free vs Premium: Free should only add on explicit user action; Premium should auto-add on zero.

### Auto-Remove on Restock (Premium vs Free)
- [ ] 1) Add a grocery item for "Test Product". Restock the item by scanning UPC 123456789012. Expected: grocery item is removed (UPC-first match).
- [ ] 2) Add a grocery item named "Milk" and restock via custom add named "Milk" (no UPC). Expected: grocery item is removed by name match.
- [ ] 3) Free vs Premium: Premium should auto-remove on restock; Free behavior may be manual unless auto-remove is triggered by add/scan flows.

### Paywall and Purchase Buttons (Premium vs Free)
- [ ] 1) Open Paywall and tap monthly/annual buttons. Expected: in-app purchase is NOT implemented; no Premium change.
- [ ] 2) Tap "Restore Purchases". Expected: no change (not implemented).
- [ ] 3) Free vs Premium: in production, StoreKit should control Premium; until then, use DEBUG simulation or backend admin tools.

### Auth, App Lock, and Session (Free vs Premium)
- [ ] 1) Verify session persistence after force quit and relaunch. Expected: still logged in (unless app lock is enabled).
- [ ] 2) Enable app lock and test 30-second grace period. Expected: lock overlay appears after >30 seconds.
- [ ] 3) Free vs Premium: behavior is the same.

### Checkout History (Free vs Premium)
- [ ] 1) Run 3-5 checkout scans. Expected: history list shows correct product names, no duplicates, no "undefined" user names.
- [ ] 2) Free vs Premium: behavior is the same.

### Toasts (Free vs Premium)
- [ ] 1) Trigger success, error, and info toasts (inventory add, limit error, grocery auto-remove). Expected: top slide-down, queue order, and correct color/haptics.
- [ ] 2) Free vs Premium: behavior is the same.

## Expected Results
- [ ] 1) Premium removes inventory and grocery limits.
- [ ] 2) Premium enables household sharing invite generation.
- [ ] 3) Auto-add and auto-remove grocery behaviors occur for Premium households.
- [ ] 4) Premium status applies to all household members.

## Notes
- [ ] 1) Premium status is household-wide (not per-user) and should display for all members.
- [ ] 2) App UI may show the grocery add prompt even for Premium; verify server-side auto-add still occurs.
- [ ] 3) Biometric login enablement is only available after password login (not Apple sign-in).

## Risks / Verify
- [ ] 1) UI limit checks use `isPremium` while grocery auto-add uses `isPremiumActive` (expiration-aware). Verify behavior when Premium expires.
- [ ] 2) Auto-remove on restock is not triggered by the + button for existing items; verify this path.
- [ ] 3) Paywall triggered from Grocery tab relies on NotificationCenter; confirm it appears reliably.

## Print Checklist
- [ ] 1) Premium badge appears and removes limits.
- [ ] 2) Household sharing invite + join works on two devices.
- [ ] 3) Checkout to zero auto-adds to grocery list.
- [ ] 4) Restock auto-removes grocery items (UPC-first, name fallback).
- [ ] 5) No paywall blocks Premium actions.
