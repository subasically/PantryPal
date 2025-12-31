# Quick Test Reference Card

## 🚀 Quick Start (1 minute)

```bash
# 1. Create test environment
curl -X POST https://api-pantrypal.subasically.me/api/test/seed \
  -H "x-test-admin-key: pantrypal-test-key-2025"

# 2. Login to iOS app
Email: test@pantrypal.com
Password: Test123!

# 3. Start testing!
```

---

## 🔑 Test Credentials

| Field | Value |
|-------|-------|
| Email | `test@pantrypal.com` |
| Password | `Test123!` |
| Admin Key | `pantrypal-test-key-2025` |

---

## 📡 Test Endpoints

```bash
# Base URL
BASE="https://api-pantrypal.subasically.me/api/test"
KEY="pantrypal-test-key-2025"

# Status check
curl -X GET $BASE/status -H "x-test-admin-key: $KEY"

# Get credentials
curl -X GET $BASE/credentials -H "x-test-admin-key: $KEY"

# Seed test data
curl -X POST $BASE/seed -H "x-test-admin-key: $KEY"

# Enable Premium (get householdId from seed response)
curl -X POST $BASE/premium/{householdId} \
  -H "x-test-admin-key: $KEY" \
  -H "Content-Type: application/json" \
  -d '{"active": true}'
```

---

## 📦 Seeded Test Data

**Locations:** Fridge, Pantry, Freezer  
**Products:** 3 with UPCs (123456789012, 123456789999, 999888777666)  
**Inventory:** 2 items (Milk in Fridge, Bread in Pantry)  
**Household:** "Test Household" (non-Premium by default)

---

## ✅ Quick Smoke Test (5 min)

- [ ] Login with test credentials
- [ ] View seeded inventory (2 items)
- [ ] Add custom item "Eggs" to Fridge
- [ ] Scan UPC 123456789012 (should find Test Product)
- [ ] Checkout UPC 123456789999 (should decrement)
- [ ] Add item to grocery list
- [ ] Pull to refresh

---

## 🔒 After Testing

```bash
# IMPORTANT: Disable test endpoints when done
ssh root@62.146.177.62 "cd /root/pantrypal-server && \
  sed -i 's/ALLOW_TEST_ENDPOINTS=true/ALLOW_TEST_ENDPOINTS=false/g' .env && \
  docker-compose restart pantrypal-api"
```

---

**Full Docs:** See `UI_TEST_VERIFICATION_COMPLETE.md` and `test-plans/` folder
