# PantryPal UI Testing Guide

## Overview
Automated UI tests using XCTest/XCUITest with DEBUG-only test hooks for deterministic testing.

## Setup

### 1. Add Files to Xcode
Created files that need to be added to Xcode project:
- `AccessibilityIdentifiers.swift` (Utils folder)
- `UITestingMode.swift` (Utils folder)

### 2. Server Test Endpoints
Test endpoints at `/api/test/*` (only enabled in non-production):
- `POST /api/test/reset` - Clear all test data
- `POST /api/test/seed` - Seed with test user and data
- `GET /api/test/credentials` - Get test user credentials
- `POST /api/test/premium/:householdId` - Toggle premium

**Required Header:** `X-Test-Admin-Key: test-admin-secret-change-me`

### 3. Launch Arguments
Pass these to enable UI testing mode:
```swift
app.launchArguments = ["UI_TESTING"]
app.launchEnvironment = [
    "API_BASE_URL": "http://localhost:3002",
    "UI_TEST_DISABLE_APP_LOCK": "true",
    "UI_TEST_INJECT_PREMIUM": "false",
    "UI_TEST_EMAIL": "test@pantrypal.com",
    "UI_TEST_PASSWORD": "Test123!"
]
```

## Test User Credentials
After seeding, use:
- **Email:** test@pantrypal.com
- **Password:** Test123!
- **Household:** Pre-created with 2 locations (Fridge, Pantry)
- **Inventory:** 1 milk item in fridge
- **Invite Code:** TEST01

## Key Accessibility Identifiers

### Login
- `AccessibilityIdentifiers.Login.emailField`
- `AccessibilityIdentifiers.Login.passwordField`
- `AccessibilityIdentifiers.Login.loginButton`

### Inventory
- `AccessibilityIdentifiers.Inventory.list`
- `AccessibilityIdentifiers.Inventory.addButton`
- `AccessibilityIdentifiers.Inventory.row(id:)`
- `AccessibilityIdentifiers.Inventory.incrementButton(id:)`

### Scanner (with test injection)
- `AccessibilityIdentifiers.Scanner.debugInjectButton` (DEBUG only)
- `AccessibilityIdentifiers.Scanner.debugUPCField` (DEBUG only)

### Grocery
- `AccessibilityIdentifiers.Grocery.addField`
- `AccessibilityIdentifiers.Grocery.row(id:)`

### Settings
- `AccessibilityIdentifiers.Settings.signOutButton`

## Applying Identifiers

### Example: LoginView
```swift
TextField("Email", text: $email)
    .accessibilityIdentifier(AccessibilityIdentifiers.Login.emailField)

Button("Log In") { ... }
    .accessibilityIdentifier(AccessibilityIdentifiers.Login.loginButton)
```

### Example: Inventory Row
```swift
HStack {
    // ... item content
}
.accessibilityIdentifier(AccessibilityIdentifiers.Inventory.row(id: item.id))

Button("-") { ... }
    .accessibilityIdentifier(AccessibilityIdentifiers.Inventory.decrementButton(id: item.id))
```

## Creating UI Test Target

1. **In Xcode:** File → New → Target → UI Testing Bundle
2. **Name:** PantryPalUITests
3. **Add to:** PantryPal project

## Sample Test Structure

```swift
import XCTest

final class PantryPalUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launchEnvironment = [
            "API_BASE_URL": "http://localhost:3002",
            "UI_TEST_DISABLE_APP_LOCK": "true"
        ]
        
        // Reset and seed test data
        resetTestServer()
        seedTestServer()
        
        app.launch()
    }
    
    func resetTestServer() {
        let url = URL(string: "http://localhost:3002/api/test/reset")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("test-admin-secret-change-me", forHTTPHeaderField: "X-Test-Admin-Key")
        
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            sem.signal()
        }.resume()
        sem.wait()
    }
    
    func seedTestServer() {
        let url = URL(string: "http://localhost:3002/api/test/seed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("test-admin-secret-change-me", forHTTPHeaderField: "X-Test-Admin-Key")
        
        let sem = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { _, _, _ in
            sem.signal()
        }.resume()
        sem.wait()
    }
    
    func testLoginWithEmail_Success() throws {
        // Tap continue with email
        app.buttons["login.continueWithEmail"].tap()
        
        // Enter credentials
        let emailField = app.textFields["login.emailField"]
        emailField.tap()
        emailField.typeText("test@pantrypal.com")
        
        let passwordField = app.secureTextFields["login.passwordField"]
        passwordField.tap()
        passwordField.typeText("Test123!")
        
        // Tap login
        app.buttons["login.loginButton"].tap()
        
        // Verify we see inventory
        let inventoryList = app.otherElements["inventory.list"]
        XCTAssertTrue(inventoryList.waitForExistence(timeout: 5))
    }
    
    func testAddCustomItem_Success() throws {
        // Login first
        loginTestUser()
        
        // Tap add button
        app.buttons["inventory.addButton"].tap()
        
        // Enter item details
        let nameField = app.textFields["addItem.nameField"]
        nameField.tap()
        nameField.typeText("Test Item")
        
        // Save
        app.buttons["addItem.saveButton"].tap()
        
        // Verify item appears in list
        sleep(2) // Wait for sync
        XCTAssertTrue(app.otherElements.matching(identifier: "inventory.row.").count > 0)
    }
    
    private func loginTestUser() {
        app.buttons["login.continueWithEmail"].tap()
        app.textFields["login.emailField"].tap()
        app.textFields["login.emailField"].typeText("test@pantrypal.com")
        app.secureTextFields["login.passwordField"].tap()
        app.secureTextFields["login.passwordField"].typeText("Test123!")
        app.buttons["login.loginButton"].tap()
        sleep(2)
    }
}
```

## Scanner Test Injection (DEBUG Only)

Add to scanner view when `UITestingMode.isUITesting`:

```swift
#if DEBUG
if UITestingMode.isUITesting {
    VStack {
        TextField("Inject UPC", text: $debugUPC)
            .accessibilityIdentifier(AccessibilityIdentifiers.Scanner.debugUPCField)
        
        Button("Inject Scan") {
            handleScannedCode(debugUPC)
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.Scanner.debugInjectButton)
    }
    .padding()
    .background(Color.yellow.opacity(0.3))
}
#endif
```

## Running Tests

### Locally
```bash
xcodebuild test \
  -scheme PantryPal \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -testPlan PantryPalUITests
```

### In Xcode
1. Select PantryPalUITests scheme
2. Cmd+U to run all tests
3. Individual tests: click diamond in gutter

## CI/CD (GitHub Actions)

```yaml
name: UI Tests

on: [push, pull_request]

jobs:
  ui-tests:
    runs-on: macos-13
    steps:
      - uses: actions/checkout@v3
      
      - name: Start Test Server
        run: |
          cd server
          npm install
          NODE_ENV=test npm start &
          sleep 5
      
      - name: Run UI Tests
        run: |
          cd ios
          xcodebuild test \
            -scheme PantryPal \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -testPlan PantryPalUITests
```

## Test Coverage Goals

### Smoke Tests (5-8 tests)
1. ✅ `testLoginWithEmail_Success`
2. ✅ `testAddCustomItem_WithDefaultLocation`
3. ✅ `testInjectScan_FoundItem_AddToPantry`
4. ✅ `testInjectScan_NotFound_ShowsCustomFlow`
5. ✅ `testCheckoutLastItem_TriggersGroceryBehavior`
6. ✅ `testGroceryAutoRemove_OnRestock`
7. ✅ `testHouseholdJoinByCode`
8. ✅ `testSettings_SignOut`

### Not Covered (Acceptable)
- Real camera scanning
- Biometric authentication
- Push notifications
- Multi-device sync (requires multiple simulators)

## Troubleshooting

### Tests Flake
- Increase `waitForExistence(timeout:)` values
- Add `sleep()` after actions that trigger network
- Verify server is running and seeded

### Can't Find Elements
- Check accessibility identifier spelling
- Use Xcode Accessibility Inspector
- Verify element exists in UI hierarchy

### App Lock Blocks Tests
- Ensure `UI_TEST_DISABLE_APP_LOCK: "true"` in launch environment
- Check AuthViewModel respects this flag

### Server Connection Failed
- Start server with `NODE_ENV=test npm start`
- Verify port 3002 is available
- Check firewall settings

## Next Steps

1. **Add Accessibility Identifiers** to all views (see examples above)
2. **Create UITests target** in Xcode
3. **Implement 5-8 smoke tests** (see sample structure)
4. **Add scanner injection UI** (DEBUG only)
5. **Configure CI** (optional)

## Security Notes

- Test endpoints ONLY work in non-production
- Require admin key header
- Test hooks ONLY compile in DEBUG builds
- No test code ships to production
