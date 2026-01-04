# PantryPal MVP Plan

## Week 1: Core Revenue Features ✅ COMPLETE
- [x] Implement 25 item free limit (inventory + grocery)
- [x] Household premium gate (invites & writes)
- [x] Paywall UI + error handling
- [x] Add structured 403 error codes
- [x] New User Onboarding Flow (Create/Join/Skip)
- [x] Manual Household Creation
- [x] Grocery List with Premium auto-add/remove
- [x] Household Switching with confirmation
- [x] Premium Simulation (DEBUG only)
- [x] Premium Badge in Settings
- [x] **Premium Lifecycle Management** ✨ NEW
  - [x] Database: premium_expires_at column
  - [x] Premium remains active until expiration (no immediate cutoff)
  - [x] Graceful downgrade (read-only above limit)
  - [x] Offline Premium caching support
  - [x] Checkout auto-add parity (qty → 0 triggers grocery add)
- [ ] One-time "household locked" banner
- [x] **In-App Purchases (StoreKit 2)** ✨ COMPLETED
  - [x] Product configuration (.storekit file)
  - [x] Purchase flow (PaywallView → StoreKitService → Server)
  - [x] Receipt validation (/api/subscriptions/validate)
  - [x] Set premium_expires_at on purchase/renewal
  - [x] Handle subscription cancellation/expiration
  - [x] Restore purchases functionality
  - [ ] Xcode: Add Configuration.storekit to build settings
  - [ ] Test: Purchase flow → confetti → Premium unlocked
  - [ ] Test: Restore purchases flow
  - [ ] Test: Sandbox account testing

## Week 2: Polish & Launch Prep
- [x] **Location & TextField Standardization** ✨ COMPLETED
  - [x] Remove "Select Location" placeholder everywhere
  - [x] Location always defaults to valid value (sticky + fallback)
  - [x] No ability to save items with invalid location
  - [x] Server validates location on all endpoints
  - [x] Standardized TextField component (AppTextField/AppSecureField)
  - [x] Consistent 44pt minimum height across all text inputs
  - [x] Applied to Login, Household Setup, Household Sharing, Grocery List
- [x] **Centralized Toast System** ✨ COMPLETED
  - [x] ToastCenter singleton with queue management
  - [x] Toast types: success, info, warning, error
  - [x] Top-aligned with slide-down animation
  - [x] Haptic feedback (success/error only)
  - [x] Auto-dismiss with configurable duration
  - [x] iPad: centered with max width constraint
  - [x] Applied globally via app root overlay
- [x] **Grocery Auto-Remove on Restock** ✨ COMPLETED
  - [x] Schema: Added brand + upc to grocery_items
  - [x] API: DELETE /by-upc/:upc and /by-name/:normalizedName
  - [x] iOS: GroceryViewModel.attemptAutoRemove() with UPC-first matching
  - [x] UI: Display brand + name in grocery list
  - [x] Hooks: Auto-remove on barcode scan, custom add, quantity increase
  - [x] Toast: Show "Removed X from grocery list" on success
- [ ] **In-App Purchases (StoreKit 2)** ← NEXT
  - [ ] Product configuration
  - [ ] Purchase flow
  - [ ] Receipt validation
  - [ ] Set premium_expires_at on purchase/renewal
  - [ ] Handle subscription cancellation
  - [ ] Restore purchases
- [x] Last-item confirmation UX
  - [x] Alert: "Add to grocery list?" when qty → 0
  - [x] Works for both manual decrement and barcode checkout
  - [x] All users get confirmation (Premium and Free)
- [ ] Premium expiration warnings
  - [ ] Alert 7 days before expiration
  - [ ] Banner on expiration day
- [ ] App Store screenshots
- [ ] Clear pricing copy
- [ ] TestFlight to friends/family
- [ ] Test household sharing flow end-to-end

## Week 3: Ship & Measure
- [ ] Ship to App Store
- [ ] Collect metrics:
    - % hitting limit
    - % upgrading
    - 7-day retention
    - Household join rate

---

## Post-MVP Features (After Revenue Validation)

### Real-Time Sync (Multi-User) ✅ IMPLEMENTED
- [x] **Polling Implemented** (60-second interval)
  - ✅ Timer-based background sync every 60s
  - ✅ Only runs when app is active/foreground
  - ✅ Stops automatically on background/inactive
  - ✅ Silent sync (no loading spinners)
  - ✅ Automatic start on app open
  - ✅ Resume on app foregrounding
  - Implementation: `InventoryListView` with Timer
  - Total work: ~30 minutes (even faster than estimated!)
  
  **Current Sync Strategy (Complete):**
  - ✅ Manual sync: Pull-to-refresh
  - ✅ Automatic sync: App open, foreground
  - ✅ Action sync: Immediate after add/update/delete
  - ✅ Background sync: 60s polling when active
  
  **Future Enhancements (if needed):**
  - ⏸️ SSE: Real-time push, 1-2 days, medium complexity
  - ⏸️ WebSocket: Best latency, 2-3 days, high complexity
  - Decision: Validate polling is sufficient before upgrading

### Data Integrity & Conflict Resolution
- [ ] **Concurrent Scan Race Condition:**
  - [ ] Issue: Two users scanning same item simultaneously can create duplicate entries
  - [ ] Current: "Last check wins" - if both pass existence check, both INSERT
  - [ ] Mitigation: 60s sync + action sync helps reconcile
  - [ ] Solutions to evaluate:
    - [ ] Database-level UNIQUE constraint on (product_id, expiration_date, location_id, household_id)
    - [ ] Use UPSERT (INSERT OR REPLACE) instead of SELECT + INSERT/UPDATE
    - [ ] Optimistic locking with version numbers
    - [ ] Advisory locks during inventory add operation
  - [ ] Priority: Low (edge case, auto-reconciles via sync)
- [ ] **Offline Conflict Resolution:**
  - [ ] Handle conflicting edits to same item from different devices
  - [ ] Conflict resolution strategies: Last-write-wins vs merge vs user prompt
  - [ ] Visual indicator for conflicted items
- [ ] **Delete Cascading:**
  - [ ] Validate all foreign key relationships handle deletes properly
  - [ ] Test household deletion with active inventory/grocery items

### Push Notifications
- [ ] Push notification setup (APNs)
- [ ] Device token registration
- [ ] Household join notifications (notify owner)
- [ ] Household leave notifications
- [ ] Low stock alerts (when qty = 0)
- [ ] Expiration reminders:
  - [ ] 30 days before expiration
  - [ ] 14 days before expiration
  - [ ] 7 days before expiration
  - [ ] Day of expiration (expired)
  - [ ] Server-side scheduled job for notifications
  - [ ] User preference settings (enable/disable per type)

### Item Organization
- [ ] **Tagging System:**
  - [ ] Database: `tags` table + `item_tags` junction table
  - [ ] UI: Multi-select tag picker in Add/Edit item
  - [ ] Tag management in Settings (create, edit, delete custom tags)
  - [ ] Predefined tags: "Organic", "Frozen", "Bulk", "Sale Item"
  - [ ] Filter inventory by tag
  - [ ] Tag-based search
  - [ ] Color-coded tag badges
  - [ ] Household-scoped tags (shared across household)
- [ ] Category organization
- [ ] Search by category/tag

### Engagement Features
- [ ] **Receipt Scanner (OCR):**
  - [ ] Camera-based receipt scanning
  - [ ] OCR text extraction (Vision framework or ML Kit)
  - [ ] Parse item names, quantities, prices from receipt
  - [ ] Present editable list of detected items for user review
  - [ ] Bulk add to inventory with adjustable quantities
  - [ ] Smart matching: Link detected items to existing products
  - [ ] Location assignment for all scanned items
  - [ ] Optional: Price tracking per item
  - [ ] Error handling: Manual entry fallback for OCR failures
  - [ ] Privacy: Process receipts on-device, no cloud storage
- [ ] **Recipe Feature:**
  - [ ] Recipe database (stored per household)
  - [ ] Recipe CRUD (create, read, update, delete)
  - [ ] Recipe fields: name, ingredients list (with quantities), instructions, servings, prep time, cook time
  - [ ] Link recipes to inventory items (ingredient matching)
  - [ ] Recipe suggestions based on current inventory
  - [ ] "Can I make this?" indicator (shows missing ingredients)
  - [ ] Add missing ingredients to grocery list from recipe
  - [ ] **Custom Favorite Recipes:**
    - [ ] User-defined recipe collections
    - [ ] Pre-loaded recipe templates (optional): Bosnian cuisine (pita, grah, čorba, etc.)
    - [ ] Category/tag system for recipes (e.g., "Bosnian", "Quick Meals", "Comfort Food")
    - [ ] Recipe sharing within household
    - [ ] Photo upload for recipes
    - [ ] Notes/variations field
  - [ ] **AI-Assisted Recipe Generation (Optional):**
    - [ ] User settings: Enable AI features + Bring Your Own Key (BYOK)
    - [ ] Secure API key storage (encrypted in user settings)
    - [ ] Generate recipes from inventory items using GPT API
    - [ ] AI recipe refinement (adjust servings, dietary restrictions, etc.)
    - [ ] Smart ingredient substitution suggestions
    - [ ] Cultural/regional recipe adaptations (e.g., "Make this Bosnian-style")
    - [ ] Recipe translation to other languages
    - [ ] Privacy: API calls made directly from user's device with their key
    - [ ] Fallback: Works offline/without API key for manual recipe entry
- [ ] Nutrition information
- [ ] Barcode scan history
- [ ] Product image display (from UPC API)
- [ ] Shopping list from recipes

### Polish
- [ ] Dark mode theme refinement
- [ ] iPad layout optimization
- [ ] Widgets for expiring items
- [ ] Siri shortcuts
- [ ] Watch app

### Analytics
- [ ] Advanced consumption analytics
- [ ] Waste tracking (what expired unused)
- [ ] Cost tracking per item
- [ ] Monthly spending reports

### Social
- [ ] Household activity feed
- [ ] Member contribution stats
- [ ] Shared shopping lists with assignments

---

## ⚠️ Ruthless MVP Rule
**DO NOT** implement post-MVP features until we validate:
1. People will pay for Premium
2. Household sharing drives upgrades
3. 25-item limit is effective

**Focus:** Reliability, Sync, Paywall, Revenue.
