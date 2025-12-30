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

### Real-Time Sync (Multi-User)
- [ ] **Decision:** Implement polling (30-60s) vs SSE vs WebSocket
  - Current: Manual sync (pull-to-refresh, app open, after actions)
  - Pain: Users don't see household changes until manual refresh
  - Options evaluated:
    - ✅ Polling: Simple, 1hr work, good enough
    - ⏸️ SSE: Real-time, 1-2 days, medium complexity
    - ⏸️ WebSocket: Best latency, 2-3 days, high complexity
  - **Verdict:** Polling is sufficient for MVP+, validate need first
  - Implementation: Timer-based sync in InventoryViewModel
  - Optimization: Only when app active, stop on background

### Push Notifications
- [ ] Push notification setup (APNs)
- [ ] Device token registration
- [ ] Household join notifications (notify owner)
- [ ] Household leave notifications
- [ ] Low stock alerts
- [ ] Expiration reminders (3 days, 1 day, expired)

### Engagement Features
- [ ] Recipe suggestions based on inventory
- [ ] Nutrition information
- [ ] Barcode scan history
- [ ] Product image display
- [ ] Category organization
- [ ] Search by category
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
