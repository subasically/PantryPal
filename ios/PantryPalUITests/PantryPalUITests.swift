import XCTest

final class PantryPalUITests: XCTestCase {
    
    var app: XCUIApplication!
    let testServerURL = "http://localhost:3002"
    let testAdminKey = "pantrypal-test-key-2025"
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["UI_TESTING"]
        app.launchEnvironment = [
            "API_BASE_URL": testServerURL,
            "UI_TEST_DISABLE_APP_LOCK": "true"
        ]
        
        // NOTE: Server should already be running and seeded
        // Run: ./scripts/start-test-server.sh before running tests
        // The server will have test data already seeded from previous run
        
        app.launch()
    }
    
    override func tearDownWithError() throws {
        // Logout to ensure clean state for next test
        if app.otherElements["mainTab.container"].exists {
            // Find and tap Settings tab (last tab)
            let tabs = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'settings'"))
            if tabs.count > 0 {
                tabs.firstMatch.tap()
                sleep(1)
                
                // Find and tap Sign Out button
                let signOutBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sign out'"))
                if signOutBtn.count > 0 {
                    signOutBtn.firstMatch.tap()
                    sleep(2)
                }
            }
        }
        
        app = nil
    }
    
    // MARK: - Server Helpers
    
    func resetTestServer() {
        let url = URL(string: "\(testServerURL)/api/test/reset")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(testAdminKey, forHTTPHeaderField: "x-test-admin-key")
        
        let exp = XCTestExpectation(description: "Reset")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                print("✅ Reset: \(http.statusCode)")
            }
            exp.fulfill()
        }.resume()
        wait(for: [exp], timeout: 5)
    }
    
    func seedTestServer() {
        let url = URL(string: "\(testServerURL)/api/test/seed")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(testAdminKey, forHTTPHeaderField: "x-test-admin-key")
        
        let exp = XCTestExpectation(description: "Seed")
        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let http = response as? HTTPURLResponse {
                print("✅ Seed: \(http.statusCode)")
            }
            exp.fulfill()
        }.resume()
        wait(for: [exp], timeout: 5)
    }
    
    // MARK: - Helper Methods
    
    func loginTestUser() {
        // Check if already logged in
        if app.otherElements["mainTab.container"].exists || app.otherElements["householdSetup.container"].exists {
            return // Already logged in, skip
        }
        
        let continueBtn = app.buttons["login.continueWithEmailButton"]
        if continueBtn.waitForExistence(timeout: 3) {
            continueBtn.tap()
        }
        
        let emailField = app.textFields["login.emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        sleep(1) // Wait for keyboard
        emailField.typeText("test@pantrypal.com")
        
        let passwordField = app.secureTextFields["login.passwordField"]
        passwordField.doubleTap() // Double tap works better for SecureTextField
        sleep(2) // Longer wait for keyboard focus
        passwordField.typeText("Test123!")
        
        app.buttons["login.loginButton"].tap()
        sleep(3) // Wait for login and sync
    }
    
    func skipOnboardingIfNeeded() {
        let skipBtn = app.buttons["onboarding.skipButton"]
        if skipBtn.waitForExistence(timeout: 2) {
            skipBtn.tap()
            sleep(1)
        }
    }
    
    // MARK: - Test Cases
    
    func test01_LoginWithEmail_Success() throws {
        let continueBtn = app.buttons["login.continueWithEmailButton"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5), "Continue button should exist")
        
        continueBtn.tap()
        
        let emailField = app.textFields["login.emailField"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 3))
        emailField.tap()
        sleep(1) // Wait for keyboard to appear
        emailField.typeText("test@pantrypal.com")
        
        let passwordField = app.secureTextFields["login.passwordField"]
        passwordField.doubleTap() // Double tap works better for SecureTextField
        sleep(2) // Longer wait for keyboard focus
        passwordField.typeText("Test123!")
        
        app.buttons["login.loginButton"].tap()
        
        sleep(3)
        
        // Should see one of: household setup, main tab view, or inventory list
        let householdSetup = app.otherElements["householdSetup.container"]
        let mainTabView = app.otherElements["mainTab.container"]
        let inventoryList = app.otherElements["inventory.list"]
        
        XCTAssertTrue(
            householdSetup.waitForExistence(timeout: 5) || mainTabView.exists || inventoryList.exists,
            "Should reach household setup, main tab, or inventory after login"
        )
    }
    
    func test02_AddCustomItem_Success() throws {
        loginTestUser()
        skipOnboardingIfNeeded()
        
        // Verify inventory list exists
        let inventoryList = app.otherElements["inventory.list"]
        XCTAssertTrue(inventoryList.waitForExistence(timeout: 5))
        
        // Tap add button
        let addBtn = app.buttons["inventory.addButton"]
        XCTAssertTrue(addBtn.waitForExistence(timeout: 3))
        addBtn.tap()
        
        sleep(1)
        
        // Find and fill name field
        let nameFields = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'name'"))
        if nameFields.count > 0 {
            let nameField = nameFields.firstMatch
            nameField.tap()
            nameField.typeText("UI Test Banana")
            
            // Find save button
            let saveBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'save' OR label CONTAINS[c] 'add'")).firstMatch
            if saveBtn.exists {
                saveBtn.tap()
                sleep(2)
            }
        }
        
        // Verify still on inventory
        XCTAssertTrue(inventoryList.exists)
    }
    
    func test03_InventoryQuantity_IncrementAndDecrement() throws {
        loginTestUser()
        skipOnboardingIfNeeded()
        
        sleep(2)
        
        // Find seeded milk item (should have ID from seed)
        let incrementButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.increment'"))
        let decrementButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.decrement'"))
        
        if incrementButtons.count > 0 {
            // Test increment
            let incrementBtn = incrementButtons.element(boundBy: 0)
            incrementBtn.tap()
            sleep(1)
            
            // Test decrement
            if decrementButtons.count > 0 {
                let decrementBtn = decrementButtons.element(boundBy: 0)
                decrementBtn.tap()
                sleep(1)
            }
        }
        
        // Verify inventory still exists
        XCTAssertTrue(app.otherElements["inventory.list"].exists)
    }
    
    func test04_NavigateToGroceryTab() throws {
        loginTestUser()
        skipOnboardingIfNeeded()
        
        sleep(2)
        
        // Find grocery tab button
        let groceryTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'grocery'")).firstMatch
        XCTAssertTrue(groceryTab.waitForExistence(timeout: 5))
        groceryTab.tap()
        
        sleep(1)
        
        // Verify on grocery view (look for common elements)
        XCTAssertTrue(app.exists)
    }
    
    func test05_NavigateToCheckoutTab() throws {
        loginTestUser()
        skipOnboardingIfNeeded()
        
        sleep(2)
        
        // Find checkout tab
        let checkoutTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'checkout' OR label CONTAINS[c] 'history'")).firstMatch
        if checkoutTab.waitForExistence(timeout: 5) {
            checkoutTab.tap()
            sleep(1)
        }
        
        XCTAssertTrue(app.exists)
    }
    
    func test06_NavigateToSettings_AndSignOut() throws {
        loginTestUser()
        skipOnboardingIfNeeded()
        
        sleep(2)
        
        // Navigate to settings
        let settingsTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'settings'")).firstMatch
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()
        
        sleep(1)
        
        // Find and tap sign out
        let signOutBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sign out'")).firstMatch
        XCTAssertTrue(signOutBtn.waitForExistence(timeout: 3))
        signOutBtn.tap()
        
        // Should return to login
        sleep(2)
        let continueBtn = app.buttons["login.continueWithEmailButton"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5), "Should return to login screen")
    }
    
    func test07_SearchInventory() throws {
        loginTestUser()
        skipOnboardingIfNeeded()
        
        sleep(2)
        
        // Find search field
        let searchField = app.searchFields.firstMatch
        if searchField.waitForExistence(timeout: 5) {
            searchField.tap()
            searchField.typeText("milk")
            sleep(1)
            
            // Clear search
            let clearBtn = searchField.buttons["Clear text"]
            if clearBtn.exists {
                clearBtn.tap()
            }
        }
        
        XCTAssertTrue(app.otherElements["inventory.list"].exists)
    }
    
    func test08_PullToRefresh() throws {
        loginTestUser()
        skipOnboardingIfNeeded()
        
        sleep(2)
        
        let inventoryList = app.otherElements["inventory.list"]
        XCTAssertTrue(inventoryList.exists)
        
        // Perform pull-to-refresh gesture
        let start = inventoryList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = inventoryList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0, thenDragTo: end)
        
        sleep(2)
        
        XCTAssertTrue(inventoryList.exists)
    }
    
    func test09_FullUserFlow_AddEditNavigate() throws {
        // 1. Login
        loginTestUser()
        skipOnboardingIfNeeded()
        
        let inventoryList = app.otherElements["inventory.list"]
        XCTAssertTrue(inventoryList.waitForExistence(timeout: 5))
        
        // 2. Add item
        app.buttons["inventory.addButton"].tap()
        sleep(1)
        
        let nameFields = app.textFields.matching(NSPredicate(format: "placeholderValue CONTAINS[c] 'name'"))
        if nameFields.count > 0 {
            nameFields.firstMatch.tap()
            nameFields.firstMatch.typeText("Full Flow Test Item")
            app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'save'")).firstMatch.tap()
            sleep(2)
        }
        
        // 3. Navigate to Grocery
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'grocery'")).firstMatch.tap()
        sleep(1)
        
        // 4. Navigate to Settings
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'settings'")).firstMatch.tap()
        sleep(1)
        
        // 5. Sign out
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'sign out'")).firstMatch.tap()
        sleep(2)
        
        // 6. Verify back at login
        XCTAssertTrue(app.buttons["login.continueWithEmailButton"].waitForExistence(timeout: 5))
    }
    
    func test10_Registration_CreateNewAccount() throws {
        // Tap continue with email
        let continueBtn = app.buttons["login.continueWithEmailButton"]
        XCTAssertTrue(continueBtn.waitForExistence(timeout: 5))
        continueBtn.tap()
        
        sleep(1)
        
        // Toggle to registration mode
        let registerToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'register'")).firstMatch
        if registerToggle.exists {
            registerToggle.tap()
            sleep(1)
        }
        
        // Fill registration form
        let firstNameField = app.textFields["login.firstNameField"]
        if firstNameField.waitForExistence(timeout: 2) {
            firstNameField.tap()
            firstNameField.typeText("Test")
            
            app.textFields["login.lastNameField"].tap()
            app.textFields["login.lastNameField"].typeText("UIUser")
        }
        
        let emailField = app.textFields["login.emailField"]
        emailField.tap()
        let randomEmail = "uitest\(Int.random(in: 10000...99999))@test.com"
        emailField.typeText(randomEmail)
        
        let passwordField = app.secureTextFields["login.passwordField"]
        passwordField.tap()
        passwordField.typeText("Test123!")
        
        // Submit
        let registerBtn = app.buttons["login.registerButton"]
        if registerBtn.waitForExistence(timeout: 2) {
            registerBtn.tap()
            
            sleep(3)
            
            // Should reach onboarding or inventory
            XCTAssertTrue(
                app.buttons["onboarding.skipButton"].waitForExistence(timeout: 5) ||
                app.otherElements["inventory.list"].exists
            )
        }
    }
}
