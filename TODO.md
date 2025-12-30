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
- [ ] One-time "household locked" banner
- [ ] Restore purchases (StoreKit integration)

## Week 2: Polish & Launch Prep
- [ ] In-App Purchases (StoreKit 2)
- [ ] Receipt validation
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
- [ ] Recipe suggestions based on inventory
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
