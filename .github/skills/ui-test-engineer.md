# UI Testing with XCTest

Run, debug, and fix PantryPal UI tests.

## When to Use
- Running UI tests
- Debugging test failures
- Adding new test cases
- Making views testable
- Fixing flaky tests

## Test Environment
- **Test File:** `ios/PantryPalUITests/PantryPalUITests.swift`
- **Test Server:** `localhost:3002`
- **Simulator:** `DEA4C9CE-5106-41AD-B36A-378A8714D172` (iPhone 16)
- **Test User:** `test@pantrypal.com` / `Test123!`
- **Admin Key:** `pantrypal-test-key-2025`

## Quick Commands

### Start Test Server
```bash
./scripts/start-test-server.sh

# Verify it's running
curl -s http://localhost:3002/health
```

### Run All Tests
```bash
cd ios && xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests
```

### Run Single Test
```bash
cd ios && xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests/PantryPalUITests/test01_LoginWithEmail_Success
```

## Accessibility Identifiers

### Naming Convention
```
<screen>.<elementType><OptionalName>
```

### Common IDs
```swift
// Login
"login.emailField"
"login.passwordField"
"login.loginButton"
"login.continueWithEmailButton"

// Inventory
"inventory.list"
"inventory.addButton"
"inventory.scanButton"

// Grocery
"grocery.list"
"grocery.addButton"

// Settings
"settings.button"
"settings.signOutButton"

// Onboarding
"householdSetup.container"
"onboarding.skipButton"

// Add Item
"addItem.nameField"
"addItem.saveButton"
```

### Adding IDs to Views
```swift
// ✅ Use string literals directly
Button("Add") { }
    .accessibilityIdentifier("inventory.addButton")

TextField("Name", text: $name)
    .accessibilityIdentifier("addItem.nameField")

List { }
    .accessibilityIdentifier("inventory.list")
```

### Using IDs in Tests
```swift
let addButton = app.buttons["inventory.addButton"]
XCTAssertTrue(addButton.waitForExistence(timeout: 3))
addButton.tap()
```

## Common Test Issues

### 1. Element Not Found
**Symptoms:** `XCTAssertTrue failed - Element doesn't exist`

**Fixes:**
```swift
// Fix 1: Add missing accessibility ID to view
Button("Save") { }.accessibilityIdentifier("addItem.saveButton")

// Fix 2: Increase timeout
XCTAssertTrue(button.waitForExistence(timeout: 5)) // Was 3

// Fix 3: Add delay before querying
sleep(1)
let button = app.buttons["addItem.saveButton"]

// Fix 4: Check correct element type
app.textFields["login.emailField"]  // ✅ Correct
app.buttons["login.emailField"]     // ❌ Wrong type
```

### 2. SecureTextField (Password) Issues
```swift
// ✅ Use doubleTap() for SecureTextField
let passwordField = app.secureTextFields["login.passwordField"]
passwordField.doubleTap()  // NOT .tap()
sleep(2)                    // Wait for keyboard
passwordField.typeText("Test123!")
```

### 3. Test Isolation (Tests Fail Together)
**Fix:** Proper tearDown
```swift
override func tearDownWithError() throws {
    if app.otherElements["mainTab.container"].exists {
        let settingsBtn = app.buttons["settings.button"]
        if settingsBtn.waitForExistence(timeout: 2) {
            settingsBtn.tap()
            sleep(1)
            
            let signOutBtn = app.buttons["settings.signOutButton"]
            if signOutBtn.waitForExistence(timeout: 2) {
                signOutBtn.tap()
                sleep(2)
            }
        }
    }
    
    app.terminate()
    app = nil
}
```

### 4. Flaky Tests (Timing Issues)
```swift
// ❌ BAD: No wait
app.buttons["login.loginButton"].tap()
let list = app.otherElements["inventory.list"]
XCTAssertTrue(list.exists)  // Might not exist yet

// ✅ GOOD: Explicit wait
app.buttons["login.loginButton"].tap()
sleep(3)  // Wait for API + navigation
let list = app.otherElements["inventory.list"]
XCTAssertTrue(list.waitForExistence(timeout: 5))
```

### 5. Loading States
```swift
// Wait for loading to finish
let loadingIndicator = app.activityIndicators.firstMatch
while loadingIndicator.exists {
    sleep(1)
}

// Now safe to query elements
let list = app.otherElements["inventory.list"]
XCTAssertTrue(list.exists)
```

## Test Debugging Workflow

### Step 1: Verify Test Server
```bash
curl -s http://localhost:3002/health
# If fails: ./scripts/start-test-server.sh
```

### Step 2: Run Failing Test
```bash
cd ios && xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests/PantryPalUITests/testXX_FailingTest
```

### Step 3: Analyze Error
- **Element not found** → Missing accessibility ID or wrong type
- **Timeout** → Need longer wait or element not rendering
- **Assertion failed** → Logic error in test
- **Interaction failed** → Element not tappable

### Step 4: Check View Code
```bash
# Find the view file
grep -r "login.emailField" ios/PantryPal/Views/
```

### Step 5: Apply Fix
- Add missing accessibility ID
- Increase timeout
- Add sleep before interaction
- Fix element type
- Improve tearDown

### Step 6: Re-run Test
```bash
cd ios && xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests/PantryPalUITests/testXX_FailingTest
```

## Helper Methods

### Login Test User
```swift
func loginTestUser() {
    if app.otherElements["mainTab.container"].exists { return }
    
    let continueBtn = app.buttons["login.continueWithEmailButton"]
    guard continueBtn.waitForExistence(timeout: 5) else { return }
    continueBtn.tap()
    
    let emailField = app.textFields["login.emailField"]
    XCTAssertTrue(emailField.waitForExistence(timeout: 3))
    emailField.tap()
    sleep(1)
    emailField.typeText("test@pantrypal.com")
    
    let passwordField = app.secureTextFields["login.passwordField"]
    passwordField.doubleTap()
    sleep(2)
    passwordField.typeText("Test123!")
    
    app.buttons["login.loginButton"].tap()
    sleep(3)
}
```

### Skip Onboarding
```swift
func skipOnboardingIfNeeded() {
    let skipBtn = app.buttons["onboarding.skipButton"]
    if skipBtn.waitForExistence(timeout: 2) {
        skipBtn.tap()
        sleep(1)
    }
}
```

## Best Practices
- ✅ Always use explicit waits (`waitForExistence`)
- ✅ Add sleeps after navigation (3s for API calls)
- ✅ Use descriptive test names: `test01_LoginWithEmail_Success`
- ✅ Clean up state in `tearDownWithError()`
- ✅ Add accessibility IDs to ALL interactive elements
- ✅ Run full suite after fixes (check for regressions)
- ✅ Use helper methods for login/navigation

## Debugging Tips
```swift
// Print element hierarchy
print(app.debugDescription)

// List all buttons
print(app.buttons.allElementsBoundByIndex.map { $0.identifier })

// Screenshot on failure
if !button.exists {
    let screenshot = XCTAttachment(screenshot: app.screenshot())
    screenshot.lifetime = .keepAlways
    add(screenshot)
}
```

## Success Metrics
- **Pass Rate:** 80%+ (all tests passing consistently)
- **Reliability:** No flaky tests
- **Speed:** Full suite completes in <5 minutes
- **Coverage:** Every user flow has at least one test
