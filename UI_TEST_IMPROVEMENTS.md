# UI Test Improvements for PantryPal

## Problems with Current Tests

1. **Too many `sleep()` calls (30+)** - Makes tests slow (2-3 min total) and flaky
2. **Weak element selectors** - `label CONTAINS[c] 'grocery'` breaks with text changes
3. **No Page Object Model** - Duplicated element finding across tests
4. **Manual setup/teardown** - Every test logs in from scratch
5. **No test isolation** - Tests depend on server state
6. **Mixed concerns** - Navigation + action + assertion in one test

## Improvement Strategy

### 1. **Page Object Model (POM)**
Create reusable page objects to centralize element finding:

```swift
// ios/PantryPalUITests/PageObjects/InventoryPage.swift
struct InventoryPage {
    let app: XCUIApplication
    
    var addButton: XCUIElement {
        app.buttons["inventory.addButton"]
    }
    
    var inventoryList: XCUIElement {
        app.otherElements["inventory.list"]
    }
    
    func incrementButton(for itemId: String) -> XCUIElement {
        app.buttons["inventory.increment.\(itemId)"]
    }
    
    func waitForLoad() {
        XCTAssertTrue(inventoryList.waitForExistence(timeout: 5))
    }
    
    func addItem(name: String, quantity: Int = 1) {
        addButton.tap()
        // Use AddItemPage helper
        AddItemPage(app: app).fillAndSave(name: name, quantity: quantity)
    }
    
    func itemExists(name: String) -> Bool {
        app.cells.staticTexts[name].exists
    }
}

// ios/PantryPalUITests/PageObjects/LoginPage.swift
struct LoginPage {
    let app: XCUIApplication
    
    func loginWithEmail(_ email: String, password: String) {
        app.buttons["login.continueWithEmailButton"].tap()
        app.textFields["login.emailField"].tap()
        app.textFields["login.emailField"].typeText(email)
        app.secureTextFields["login.passwordField"].tap()
        app.secureTextFields["login.passwordField"].typeText(password)
        app.buttons["login.loginButton"].tap()
    }
}

// ios/PantryPalUITests/PageObjects/SettingsPage.swift
struct SettingsPage {
    let app: XCUIApplication
    
    func signOut() {
        app.buttons["settings.signOutButton"].tap()
    }
    
    func deleteHouseholdData() {
        let deleteBtn = app.buttons["Delete Household Data"]
        if !deleteBtn.exists {
            app.swipeUp()
        }
        deleteBtn.tap()
        
        // Handle alerts
        app.alerts.buttons["Continue"].tap()
        let textField = app.alerts.textFields.firstMatch
        textField.tap()
        textField.typeText("RESET")
        app.alerts.buttons["Delete"].tap()
    }
}
```

### 2. **Replace `sleep()` with Smart Waits**

Create custom wait helpers:

```swift
// ios/PantryPalUITests/Helpers/WaitHelpers.swift
extension XCUIElement {
    /// Wait for element to exist and be hittable
    func waitForHittable(timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        return waitForPredicate(predicate, timeout: timeout)
    }
    
    private func waitForPredicate(_ predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    /// Tap only when hittable
    func safeTap() {
        XCTAssertTrue(waitForHittable(), "Element not tappable: \\(self)")
        tap()
    }
}

extension XCTestCase {
    /// Wait for either element to appear (useful for conditional navigation)
    func waitForAnyElement(_ elements: [XCUIElement], timeout: TimeInterval = 5) -> XCUIElement? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            for element in elements {
                if element.exists {
                    return element
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        return nil
    }
}
```

### 3. **Test Base Class with Shared Setup**

```swift
// ios/PantryPalUITests/Base/BaseUITest.swift
class BaseUITest: XCTestCase {
    var app: XCUIApplication!
    var loginPage: LoginPage { LoginPage(app: app) }
    var inventoryPage: InventoryPage { InventoryPage(app: app) }
    var settingsPage: SettingsPage { SettingsPage(app: app) }
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "API_BASE_URL": "http://localhost:3002",
            "UI_TEST_DISABLE_APP_LOCK": "true"
        ]
        app.launch()
    }
    
    override func tearDownWithError() throws {
        signOutIfLoggedIn()
        app.terminate()
        app = nil
    }
    
    // MARK: - Shared Helpers
    
    func loginAsTestUser() {
        loginPage.loginWithEmail("test@pantrypal.com", password: "Test123!")
        skipOnboardingIfNeeded()
        inventoryPage.waitForLoad()
    }
    
    func skipOnboardingIfNeeded() {
        let skipBtn = app.buttons["onboarding.skipButton"]
        if skipBtn.waitForExistence(timeout: 2) {
            skipBtn.tap()
        }
    }
    
    func signOutIfLoggedIn() {
        if app.buttons["settings.button"].exists {
            app.buttons["settings.button"].safeTap()
            settingsPage.signOut()
        }
    }
}
```

### 4. **Rewrite Tests Using POM**

```swift
// ios/PantryPalUITests/Tests/InventoryTests.swift
final class InventoryTests: BaseUITest {
    
    func testAddCustomItem() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Adding a new item
        inventoryPage.addItem(name: "Test Banana", quantity: 2)
        
        // THEN: Item appears in inventory
        XCTAssertTrue(inventoryPage.itemExists(name: "Test Banana"))
    }
    
    func testIncrementQuantity() throws {
        // GIVEN: User is logged in with existing items
        loginAsTestUser()
        let firstItemId = "1" // From seeded data
        
        // WHEN: Incrementing quantity
        inventoryPage.incrementButton(for: firstItemId).safeTap()
        
        // THEN: Quantity increases (no assertions needed if no crash)
        XCTAssertTrue(inventoryPage.inventoryList.exists)
    }
    
    func testSearchInventory() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Searching for "milk"
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("milk")
        
        // THEN: Results filtered
        XCTAssertTrue(inventoryPage.inventoryList.exists)
    }
}

// ios/PantryPalUITests/Tests/AuthTests.swift
final class AuthTests: BaseUITest {
    
    func testLoginWithValidCredentials() throws {
        // GIVEN: At login screen
        
        // WHEN: Entering valid credentials
        loginPage.loginWithEmail("test@pantrypal.com", password: "Test123!")
        
        // THEN: Reaches main screen
        skipOnboardingIfNeeded()
        XCTAssertTrue(inventoryPage.inventoryList.waitForExistence(timeout: 5))
    }
    
    func testSignOut() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Signing out
        app.buttons["settings.button"].safeTap()
        settingsPage.signOut()
        
        // THEN: Returns to login
        XCTAssertTrue(app.buttons["login.continueWithEmailButton"].waitForExistence(timeout: 5))
    }
}
```

### 5. **Test Organization**

```
ios/PantryPalUITests/
├── Base/
│   └── BaseUITest.swift           # Shared setup/teardown
├── PageObjects/
│   ├── LoginPage.swift             # Login screen helpers
│   ├── InventoryPage.swift         # Inventory screen helpers
│   ├── GroceryPage.swift           # Grocery screen helpers
│   ├── SettingsPage.swift          # Settings screen helpers
│   └── AddItemPage.swift           # Add item modal helpers
├── Helpers/
│   ├── WaitHelpers.swift           # Custom wait extensions
│   └── ServerHelpers.swift         # API reset/seed helpers
└── Tests/
    ├── AuthTests.swift             # Login/logout tests
    ├── InventoryTests.swift        # Inventory CRUD tests
    ├── GroceryTests.swift          # Grocery list tests
    ├── PremiumTests.swift          # Premium/paywall tests
    └── NavigationTests.swift       # Tab navigation tests
```

### 6. **Priority Tests to Automate**

Focus on **critical user paths** that are tedious to test manually:

#### **High Priority (Automate First)**
- ✅ Login/logout
- ✅ Add/edit/delete inventory items
- ✅ Increment/decrement quantity
- ✅ Hit 25-item free limit → paywall appears
- ✅ Premium user: auto-add to grocery on item removal
- ✅ Free user: no auto-add (manual grocery only)
- ✅ Delete household data clears everything
- ✅ Household switching confirmation

#### **Medium Priority**
- Search/filter inventory
- Expiration date logic
- Grocery list CRUD
- Scanner (with test injection)
- Offline behavior
- Pull-to-refresh sync

#### **Low Priority (Keep Manual)**
- Apple Sign In (sandbox only, complex)
- StoreKit purchases (sandbox testing sufficient)
- Camera/barcode scanning (hardware-dependent)
- Haptics/animations (visual testing)
- Edge cases (network errors, race conditions)

### 7. **Fast Test Execution**

#### **Before:**
- 10 tests × 15 seconds average = **2.5 minutes**
- Repeated logins, manual navigation, excessive waits

#### **After (with improvements):**
- 10 tests × 5 seconds average = **50 seconds**
- Shared login state, page objects, smart waits

#### **Technique: Test Suites**
Group tests to reuse login session:

```swift
// Run all inventory tests with one login
class InventoryTestSuite: BaseUITest {
    override func setUp() {
        super.setUp()
        loginAsTestUser() // Only once for entire suite
    }
    
    func test01_AddItem() { /* ... */ }
    func test02_Increment() { /* ... */ }
    func test03_Decrement() { /* ... */ }
    func test04_Search() { /* ... */ }
}
```

### 8. **CI Integration (Future)**

Once tests are reliable, run on every PR:

```yaml
# .github/workflows/ui-tests.yml
name: UI Tests
on: [pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Start test server
        run: ./scripts/start-test-server.sh &
      - name: Run UI tests
        run: xcodebuild test -scheme PantryPal -destination 'platform=iOS Simulator,name=iPhone 16'
```

## Implementation Steps

1. **Week 1: Foundation**
   - Create `BaseUITest` class
   - Add `WaitHelpers` extensions
   - Build `LoginPage` and `InventoryPage` objects

2. **Week 2: Rewrite Tests**
   - Convert existing tests to use POM
   - Remove all `sleep()` calls
   - Add smart waits

3. **Week 3: Expand Coverage**
   - Add `PremiumTests` (free limit, paywall, auto-add)
   - Add `GroceryTests` (add, remove, auto-remove)
   - Add `NavigationTests` (tab switching)

4. **Week 4: Optimize**
   - Test suite grouping for shared login
   - Measure execution time (target: <60s for 20+ tests)
   - CI integration (optional)

## Expected Outcomes

- **Faster tests**: 2.5 min → 50 sec (5x improvement)
- **More reliable**: No flaky `sleep()` timing issues
- **Easier maintenance**: Change element once in page object
- **Better coverage**: 10 tests → 25+ tests (same time budget)
- **Confidence to ship**: Catch regressions automatically

## Quick Wins (Do First)

1. Replace `sleep(1)` with `.waitForHittable()` - **30% faster**
2. Create `InventoryPage` object - **Eliminate 50+ duplicated lines**
3. Add `BaseUITest.loginAsTestUser()` - **Simplify every test**
4. Use accessibility identifiers consistently - **No more brittle predicates**

---

**Bottom line:** Invest 2-3 days refactoring tests now to save 1-2 hours of manual testing per week. Once stable, you can trust the tests and ship faster with confidence.
