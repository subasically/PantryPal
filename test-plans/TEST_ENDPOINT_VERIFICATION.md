# Test Endpoint Verification

## ✅ Status: Test Endpoints Enabled on Production

**Server:** https://api-pantrypal.subasically.me  
**Test Base URL:** https://api-pantrypal.subasically.me/api/test  
**Admin Key:** `pantrypal-test-key-2025`  
**Header:** `x-test-admin-key: pantrypal-test-key-2025`

---

## Available Test Endpoints

### 1. Status Check
**Endpoint:** `GET /api/test/status`  
**Purpose:** Verify test endpoints are active  
**Auth:** Requires admin key  

```bash
curl -X GET https://api-pantrypal.subasically.me/api/test/status \
  -H "x-test-admin-key: pantrypal-test-key-2025"
```

**Expected Response:**
```json
{
  "enabled": true,
  "message": "Test endpoints are active",
  "timestamp": "2025-12-31T16:30:30.866Z"
}
```

---

### 2. Get Test Credentials
**Endpoint:** `GET /api/test/credentials`  
**Purpose:** Get test user login credentials  
**Auth:** Requires admin key  

```bash
curl -X GET https://api-pantrypal.subasically.me/api/test/credentials \
  -H "x-test-admin-key: pantrypal-test-key-2025"
```

**Expected Response:**
```json
{
  "email": "test@pantrypal.com",
  "password": "Test123!"
}
```

---

### 3. Reset Database
**Endpoint:** `POST /api/test/reset`  
**Purpose:** Clear all test data (use with caution!)  
**Auth:** Requires admin key  

```bash
curl -X POST https://api-pantrypal.subasically.me/api/test/reset \
  -H "x-test-admin-key: pantrypal-test-key-2025"
```

**Expected Response:**
```json
{
  "message": "Database reset complete"
}
```

⚠️ **WARNING:** This deletes ALL data including users, households, inventory, etc.

---

### 4. Seed Test Data
**Endpoint:** `POST /api/test/seed`  
**Purpose:** Create a complete test environment  
**Auth:** Requires admin key  

```bash
curl -X POST https://api-pantrypal.subasically.me/api/test/seed \
  -H "x-test-admin-key: pantrypal-test-key-2025"
```

**Expected Response:**
```json
{
  "message": "Test data seeded successfully",
  "testUser": {
    "email": "test@pantrypal.com",
    "password": "Test123!",
    "householdId": "<uuid>",
    "inviteCode": "TEST01"
  },
  "seededData": {
    "users": 1,
    "households": 1,
    "locations": 2,
    "products": 3,
    "inventory": 1,
    "grocery": 0
  }
}
```

**What Gets Created:**
- Test user: `test@pantrypal.com` / `Test123!`
- Household: "Test Household" with invite code `TEST01`
- Locations: "Fridge", "Pantry"
- Products:
  - Test Product (Brand: Test Brand, UPC: 123456789012)
  - Checkout Test Product (Brand: Test Brand, UPC: 123456789999)
  - Custom Product With UPC (Brand: Custom Brand, UPC: 999888777666)
- Initial inventory: 1x "Test Product" in Fridge (qty: 2)

---

### 5. Set Premium Status
**Endpoint:** `POST /api/test/premium/:householdId`  
**Purpose:** Toggle Premium status for testing  
**Auth:** Requires admin key  

```bash
# Enable Premium
curl -X POST "https://api-pantrypal.subasically.me/api/test/premium/{householdId}" \
  -H "x-test-admin-key: pantrypal-test-key-2025" \
  -H "Content-Type: application/json" \
  -d '{"active": true}'

# Disable Premium
curl -X POST "https://api-pantrypal.subasically.me/api/test/premium/{householdId}" \
  -H "x-test-admin-key: pantrypal-test-key-2025" \
  -H "Content-Type: application/json" \
  -d '{"active": false}'
```

**Expected Response:**
```json
{
  "message": "Premium status updated",
  "householdId": "<uuid>",
  "premiumActive": true,
  "premiumExpiresAt": "2099-12-31T23:59:59.000Z"
}
```

---

## UI Test Integration

### iOS App Configuration

**For local development server:**
```swift
app.launchEnvironment = [
    "API_BASE_URL": "http://localhost:3002",
    "TEST_ADMIN_KEY": "pantrypal-test-key-2025"
]
```

**For production test server:**
```swift
app.launchEnvironment = [
    "API_BASE_URL": "https://api-pantrypal.subasically.me",
    "TEST_ADMIN_KEY": "pantrypal-test-key-2025"
]
```

---

### Test Setup Pattern

```swift
class PantryPalUITests: XCTestCase {
    
    var app: XCUIApplication!
    let baseURL = "https://api-pantrypal.subasically.me"
    let adminKey = "pantrypal-test-key-2025"
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        // Reset and seed test data
        resetTestServer()
        seedTestServer()
        
        // Configure app
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launchEnvironment = [
            "API_BASE_URL": baseURL,
            "TEST_ADMIN_KEY": adminKey,
            "UI_TEST_DISABLE_APP_LOCK": "true"
        ]
        
        app.launch()
    }
    
    func resetTestServer() {
        let url = URL(string: "\(baseURL)/api/test/reset")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(adminKey, forHTTPHeaderField: "x-test-admin-key")
        
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            sem.signal()
        }.resume()
        sem.wait()
    }
    
    func seedTestServer() {
        let url = URL(string: "\(baseURL)/api/test/seed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(adminKey, forHTTPHeaderField: "x-test-admin-key")
        
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            sem.signal()
        }.resume()
        sem.wait()
    }
    
    func enablePremium(householdId: String) {
        let url = URL(string: "\(baseURL)/api/test/premium/\(householdId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(adminKey, forHTTPHeaderField: "x-test-admin-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["active": true])
        
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            sem.signal()
        }.resume()
        sem.wait()
    }
}
```

---

## Verification Checklist

### ✅ Endpoint Availability
- [x] `/api/test/status` returns 200 with proper auth
- [x] `/api/test/status` returns 403 without auth
- [x] `/api/test/credentials` returns test user info
- [x] All endpoints require `x-test-admin-key` header
- [x] Endpoints only work when `ALLOW_TEST_ENDPOINTS=true`

### ⚠️ Security Verification
- [x] Test endpoints are disabled by default in production
- [x] Require explicit `ALLOW_TEST_ENDPOINTS=true` env var
- [x] All endpoints require admin key authentication
- [x] Returns 404 when disabled (not 403, to hide existence)
- [x] Admin key is configurable via `TEST_ADMIN_KEY` env var

### 📋 Test Data Verification
Run these tests after calling `/api/test/seed`:

```bash
# 1. Login with test credentials
curl -X POST https://api-pantrypal.subasically.me/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@pantrypal.com","password":"Test123!"}'

# 2. Verify household exists with invite code
# (Use JWT from login response)
curl -X GET https://api-pantrypal.subasically.me/api/auth/household \
  -H "Authorization: Bearer <JWT_TOKEN>"

# 3. Verify inventory items exist
curl -X GET https://api-pantrypal.subasically.me/api/inventory \
  -H "Authorization: Bearer <JWT_TOKEN>"

# 4. Verify locations exist
curl -X GET https://api-pantrypal.subasically.me/api/locations \
  -H "Authorization: Bearer <JWT_TOKEN>"
```

---

## Manual UI Test Execution

### Free Tier Tests (Using Test Endpoints)

**Setup:**
1. Call `/api/test/reset` to clear data
2. Call `/api/test/seed` to create test environment
3. Login to iOS app with `test@pantrypal.com` / `Test123!`

**Tests:**
- [ ] Login with test credentials succeeds
- [ ] Inventory shows 1 item (Test Product in Fridge, qty: 2)
- [ ] Can add custom item "Milk" to Pantry
- [ ] Can scan UPC 123456789012 and find existing product
- [ ] Can scan UPC 000000000000 and get "not found" flow
- [ ] Checkout scan of UPC 123456789999 decrements quantity
- [ ] Hitting 25 item limit shows paywall
- [ ] Grocery list manual add/remove works
- [ ] Pull-to-refresh syncs correctly

### Premium Tier Tests (Using Test Endpoints)

**Setup:**
1. Call `/api/test/reset` to clear data
2. Call `/api/test/seed` to create test environment
3. Get household ID from seed response
4. Call `/api/test/premium/{householdId}` with `{"active": true}`
5. Login to iOS app with `test@pantrypal.com` / `Test123!`

**Tests:**
- [ ] Premium badge visible in Settings
- [ ] Can add 30+ inventory items without paywall
- [ ] Can add 30+ grocery items without paywall
- [ ] Household Sharing → Generate Invite works
- [ ] Checkout to zero auto-adds to grocery list
- [ ] Restocking auto-removes from grocery list
- [ ] Second device can join via invite code `TEST01`

---

## Troubleshooting

### Test Endpoints Not Working
```bash
# Check if endpoints are enabled
ssh root@62.146.177.62 'docker exec pantrypal-server-pantrypal-api-1 printenv | grep ALLOW_TEST'
# Should show: ALLOW_TEST_ENDPOINTS=true

# Check server logs
ssh root@62.146.177.62 'docker logs pantrypal-server-pantrypal-api-1 --tail=20'
# Should show: "⚠️  [DEV] Test endpoints enabled at /api/test"
```

### 403 Forbidden
- Verify `x-test-admin-key` header is set correctly
- Key is case-sensitive: `pantrypal-test-key-2025`

### 404 Not Found
- Test endpoints are disabled on server
- Check `ALLOW_TEST_ENDPOINTS` env var
- Rebuild container with `docker-compose down && docker-compose up -d --build`

### Database Not Resetting
- Verify admin key is correct
- Check server logs for errors during `/reset` call
- SQLite database may be locked (restart container)

---

## Production Safety

**Environment Variables:**
```env
NODE_ENV=production
ALLOW_TEST_ENDPOINTS=true         # ⚠️ ONLY for testing, disable after
TEST_ADMIN_KEY=pantrypal-test-key-2025
```

**⚠️ IMPORTANT:**
1. Test endpoints should be **disabled in production** normally
2. Only enable during active UI testing sessions
3. After testing, set `ALLOW_TEST_ENDPOINTS=false` and restart
4. Test endpoints will NOT work if this env var is missing or false
5. Keep admin key secret and rotate regularly

**Disable After Testing:**
```bash
ssh root@62.146.177.62 "cd /root/pantrypal-server && \
  sed -i 's/ALLOW_TEST_ENDPOINTS=true/ALLOW_TEST_ENDPOINTS=false/g' .env && \
  docker-compose restart pantrypal-api"
```

---

## Next Steps

1. **Implement UI Tests** using the test endpoint setup pattern above
2. **Add Accessibility Identifiers** to all iOS views (see UI_TESTING_GUIDE.md)
3. **Create XCUITest Target** in Xcode
4. **Write 8-10 Smoke Tests** covering:
   - Login flow
   - Inventory add/edit/delete
   - Barcode scanning
   - Checkout flow
   - Grocery list operations
   - Premium features
   - Household join/invite
5. **Run Tests Against Production** test server
6. **Set up CI/CD** (optional) for automated testing

---

## Summary

✅ Test endpoints are **live and functional** on production  
✅ All security measures in place (admin key required)  
✅ Seed data creates complete test environment  
✅ Ready for UI test implementation  

**Test Server:** https://api-pantrypal.subasically.me  
**Admin Key:** `pantrypal-test-key-2025`  
**Test User:** `test@pantrypal.com` / `Test123!`  
**Invite Code:** `TEST01`
