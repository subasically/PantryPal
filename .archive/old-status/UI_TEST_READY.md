# UI Test Environment - SERVER MUST STAY RUNNING

**Date:** December 31, 2025  
**Status:** ⚠️ **IMPORTANT: Keep test server running during tests!**

---

## ⚠️ CRITICAL: Test Server Management

**THE PROBLEM:** Tests failed because the server exited after seeding.

**THE SOLUTION:** Use the helper scripts to keep the server running.

### Quick Start (Use This!)

```bash
# Terminal 1: Start and KEEP server running
./scripts/start-test-server.sh
# Server will stay running until you stop it

# Terminal 2: Run tests (or use Xcode Cmd+U)
cd ios
xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests

# When done: Stop server
./scripts/stop-test-server.sh
```

---

## ✅ What's Fixed

### 1. Test Server Configuration
- ✅ Tests use `localhost:3002` (NOT production)
- ✅ Missing `syncLogger` service created
- ✅ Fresh database with correct schema
- ✅ Test endpoints enabled and working

### 2. Local Test Server Running
```bash
# Currently running on PID 91911
curl http://localhost:3002/health
# {"status":"ok","timestamp":"2025-12-31T16:55:05.218Z"}

curl http://localhost:3002/api/test/status -H "x-test-admin-key: pantrypal-test-key-2025"
# {"enabled":true,"message":"Test endpoints are active"}
```

### 3. Test Data Seeded
```bash
curl -X POST http://localhost:3002/api/test/seed \
  -H "x-test-admin-key: pantrypal-test-key-2025"
# ✅ Success! Test user created: test@pantrypal.com / Test123!
```

---

## 🚀 Run UI Tests NOW

### Option 1: Via Xcode (Recommended)
```bash
# 1. Open project in Xcode
open ios/PantryPal.xcodeproj

# 2. Press Cmd+U to run all UI tests
# Or right-click PantryPalUITests and select "Run"
```

### Option 2: Via Command Line
```bash
cd ios
xcodebuild test \
  -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests
```

---

## 🔧 Test Server Management

### Start Test Server
```bash
cd server
npm run test:server

# Or with Docker Compose:
docker-compose -f docker-compose.test.yml up -d
```

### Stop Test Server
```bash
# Find PID
ps aux | grep "node src/index.js" | grep -v grep

# Kill it
kill <PID>

# Or stop Docker:
docker-compose -f docker-compose.test.yml down
```

### Reset Test Environment
```bash
# Stop server
kill <PID>

# Delete local test DB
rm server/db/*.db*

# Restart server (creates fresh DB)
cd server && npm run test:server
```

---

## 📋 Current Test Suite

| # | Test Name | Status |
|---|-----------|--------|
| 1 | `test01_LoginWithEmail_Success` | Ready |
| 2 | `test02_AddCustomItem_Success` | Ready |
| 3 | `test03_InventoryQuantity_IncrementAndDecrement` | Ready |
| 4 | `test04_NavigateToGroceryTab` | Ready |
| 5 | `test05_NavigateToCheckoutTab` | Ready |
| 6 | `test06_NavigateToSettings_AndSignOut` | Ready |
| 7 | `test07_SearchInventory` | Ready |
| 8 | `test08_PullToRefresh` | Ready |
| 9 | `test09_FullUserFlow_AddEditNavigate` | Ready |
| 10 | `test10_Registration_CreateNewAccount` | Ready |

**Total: 10 tests ready to run**

---

## ⚠️ Known Issues

### Xcode Scheme Configuration
If tests don't run, you may need to enable the UI test target:

1. Open Xcode
2. Product → Scheme → Edit Scheme
3. Select "Test" tab
4. Check ✅ `PantryPalUITests`
5. Ensure "Run" checkbox is enabled
6. Click "Close"

### Simulator Selection
Available simulators:
- iPhone 16 (ID: `DEA4C9CE-5106-41AD-B36A-378A8714D172`) ← Use this
- iPhone 16 Plus
- iPhone 16 Pro
- iPhone 16 Pro Max

If iPhone 16 doesn't work, try another simulator from the list.

---

## 🎯 Test Verification Steps

### 1. Verify Test Server
```bash
# Health check
curl http://localhost:3002/health

# Test endpoints
curl http://localhost:3002/api/test/status \
  -H "x-test-admin-key: pantrypal-test-key-2025"

# Seed data
curl -X POST http://localhost:3002/api/test/seed \
  -H "x-test-admin-key: pantrypal-test-key-2025"
```

### 2. Verify Login Flow
```bash
curl -X POST http://localhost:3002/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@pantrypal.com","password":"Test123!"}'
# Should return JWT token
```

### 3. Run Single Test
```bash
cd ios
xcodebuild test \
  -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests/PantryPalUITests/test01_LoginWithEmail_Success
```

---

## 📊 Why Local Testing?

| Aspect | Local (localhost:3002) | Production |
|--------|----------------------|------------|
| **Safety** | ✅ Isolated test DB | ❌ Could corrupt real data |
| **Speed** | ✅ Fast (no network) | ❌ Slow (API latency) |
| **Reliability** | ✅ Consistent | ❌ Network issues |
| **Reset Data** | ✅ Can reset freely | ❌ Would delete user data |
| **Offline** | ✅ Works offline | ❌ Requires internet |
| **CI/CD** | ✅ Easy to automate | ❌ Requires VPN/secrets |

---

## 🔄 Full Test Workflow

### Development Loop
```bash
# Terminal 1: Run test server
cd server
npm run test:server

# Terminal 2: Run tests (or use Xcode)
cd ios
xcodebuild test -scheme PantryPal \
  -destination '...' \
  -only-testing:PantryPalUITests

# Make changes to app...

# Re-run tests (server stays running)
```

### CI/CD Integration
```yaml
# .github/workflows/ui-tests.yml
jobs:
  ui-tests:
    runs-on: macos-13
    steps:
      - uses: actions/checkout@v3
      
      - name: Start Test Server
        run: |
          cd server
          npm ci
          npm run test:server &
          sleep 10
      
      - name: Run UI Tests
        run: |
          cd ios
          xcodebuild test -scheme PantryPal \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -only-testing:PantryPalUITests
```

---

## 📁 New Files Added

1. **`server/docker-compose.test.yml`** - Docker test environment
2. **`server/.env.test`** - Test environment variables (in .gitignore)
3. **`server/src/services/syncLogger.js`** - Missing service (fixed)
4. **`TEST_SERVER_SETUP.md`** - Complete setup guide
5. **`package.json`** - Added `test:server` script

---

## ✅ Summary

**Question:** "Are all UI tests passing?"

**Previous Answer:** ❌ Tests couldn't run (wrong config, missing service)

**Current Answer:** ⏳ **Ready to run** - all blocking issues fixed:
- ✅ Local test server running
- ✅ Missing `syncLogger` service created
- ✅ Test data seeded successfully
- ✅ Tests configured for `localhost:3002`
- ⚠️ Need to run tests to confirm all pass

**Next Step:** Run tests in Xcode (`Cmd+U`) or via command line

---

**Test Server:** http://localhost:3002  
**Admin Key:** `pantrypal-test-key-2025`  
**Test Credentials:** `test@pantrypal.com` / `Test123!`  
**Status:** ✅ READY TO TEST
