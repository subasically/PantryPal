# Debug Failing UI Test

Systematically debug a failing UI test.

## When to Use
- User says "why is test X failing?", "debug test X", "test X is broken"
- After test run shows failures
- When investigating specific test issues

## Debugging Process

### Step 1: Get Test Failure Details
```bash
# Run single test with verbose output
cd ios && xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests/PantryPalUITests/testXX_TestName \
  2>&1 | tee /tmp/test-debug.log
```

### Step 2: Analyze Failure Point
Look for:
- `error:` lines showing what failed
- `XCTAssertTrue failed` - assertion failures
- `waitForExistence` timeouts - element not found
- `Connection refused` - test server down
- `Failed to synthesize event` - UI interaction failed

### Step 3: Check Accessibility IDs
```bash
# Verify the identifier exists in the view
grep "accessibilityIdentifier.*test.element" ios/PantryPal/Views/*.swift
```

### Step 4: Check Test Server
```bash
# Verify server is running and has test data
curl -s http://localhost:3002/api/test/status
```

### Step 5: Common Issues & Fixes

**Issue:** "Element not found" / waitForExistence timeout
- **Fix:** Check accessibility identifier in the view file
- **Fix:** Increase wait timeout (change `timeout: 2` to `timeout: 5`)

**Issue:** "Connection refused"
- **Fix:** Start test server: `./scripts/start-test-server.sh`

**Issue:** "Failed to synthesize event" on SecureTextField
- **Fix:** Use `.doubleTap()` instead of `.tap()`
- **Fix:** Add `sleep(1)` after tapping field

**Issue:** Test passes first time, fails subsequent runs
- **Fix:** Logout not working - check `tearDown()` in test file
- **Fix:** Add sleep after logout: `sleep(2)`

**Issue:** "Neither element nor descendant has keyboard focus"
- **Fix:** Use `.doubleTap()` to gain focus
- **Fix:** Add delay: `sleep(1)` before typing

### Step 6: UI Hierarchy Inspection
```bash
# Extract UI hierarchy from test logs
grep -A 20 "Element debug description:" /tmp/test-debug.log
```

This shows:
- All available elements
- Their identifiers
- Their positions
- Parent-child relationships

### Step 7: Run Test Again
After making fixes, re-run the specific test:
```bash
cd ios && xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests/PantryPalUITests/testXX_TestName \
  2>&1 | grep -E "(passed|failed)"
```

## Quick Reference

### Test File Location
`ios/PantryPalUITests/PantryPalUITests.swift`

### Common Accessibility IDs
- `login.continueWithEmailButton`
- `login.emailField`
- `login.passwordField`
- `login.loginButton`
- `inventory.list`
- `inventory.addButton`
- `grocery.list`
- `checkout.tabButton`
- `settings.button`
- `settings.signOutButton`

### Test Helper Functions
- `loginTestUser()` - Login with test credentials
- `resetTestEnvironment()` - Reset test data
- `seedTestData()` - Add test items

## Example Debugging Session
```
User: "Why is test02 failing?"

You:
1. Running test02_AddCustomItem_Success...
2. Found failure: "inventory.addButton" not found (timeout after 3s)
3. Checking InventoryListView.swift...
4. Found: Button has ID "inventory.addButton" ✓
5. Issue: Button might be covered by loading state
6. Fix: Wait for loading to complete first
7. Updated test to check `!viewModel.isLoading`
8. Re-running test... ✅ PASSED!
```

## Pro Tips
- Always check test server first
- Most failures are timing issues (add sleeps)
- Use `.firstMatch` for duplicate elements
- Run tests in isolation to avoid state issues
- Check git diff to see what changed recently
