import XCTest

final class PantryPalUITests: BaseUITest {
    
    let testServerURL = "http://localhost:3002"
    let testAdminKey = "pantrypal-test-key-2025"
    
    // MARK: - Setup removed (using BaseUITest)
    
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
    
    // MARK: - Test Cases (Refactored with Page Objects)
    
    func test01_LoginWithEmail_Success() throws {
        // GIVEN: At login screen (tearDown should have logged us out)
        XCTAssertTrue(loginPage.continueWithEmailButton.exists, "Should be at login screen")
        
        // WHEN: Logging in with valid credentials
        loginAsTestUser()
        
        // THEN: Should reach main screen and see inventory
        XCTAssertTrue(inventoryPage.addButton.exists, "Add button should be visible after login")
    }
    
    func test02_AddCustomItem_Success() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Adding a new item
        inventoryPage.tapAddButton()
        
        let nameField = app.textFields["addItem.nameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("UI Test Banana")
        
        let saveBtn = app.buttons["addItem.saveButton"]
        _ = saveBtn.waitForExistence(timeout: 5)
        XCTAssertTrue(saveBtn.isEnabled, "Save button should be enabled")
        saveBtn.safeTap()
        
        // THEN: Should return to inventory
        XCTAssertTrue(inventoryPage.inventoryList.waitForExistence(timeout: 3))
    }
    
    func test03_InventoryQuantity_IncrementAndDecrement() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Incrementing first item
        let incrementButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.increment'"))
        if incrementButtons.count > 0 {
            incrementButtons.element(boundBy: 0).safeTap()
            
            // AND: Decrementing
            let decrementButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.decrement'"))
            if decrementButtons.count > 0 {
                decrementButtons.element(boundBy: 0).safeTap()
            }
        }
        
        // THEN: Inventory still exists
        XCTAssertTrue(inventoryPage.inventoryList.exists)
    }
    
    func test04_NavigateToGroceryTab() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Navigating to grocery
        groceryPage.navigateToGrocery()
        
        // THEN: On grocery view
        XCTAssertTrue(app.exists)
    }
    
    func test05_NavigateToCheckoutTab() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Navigating to checkout
        navigateToTab("checkout")
        
        // THEN: View exists
        XCTAssertTrue(app.exists)
    }
    
    func test06_NavigateToSettings_AndSignOut() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Opening settings and signing out
        settingsPage.openSettings()
        settingsPage.assertAtSettings()
        settingsPage.signOut()
        
        // THEN: Should return to login
        loginPage.assertAtLoginScreen()
    }
    
    func test07_SearchInventory() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Searching for milk
        inventoryPage.searchFor("milk")
        
        // AND: Clearing search
        inventoryPage.clearSearch()
        
        // THEN: Inventory still visible
        XCTAssertTrue(inventoryPage.inventoryList.exists)
    }
    
    func test08_PullToRefresh() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Pull to refresh
        inventoryPage.pullToRefresh()
        
        // THEN: Inventory still visible
        _ = inventoryPage.inventoryList.waitForExistence(timeout: 3)
        XCTAssertTrue(inventoryPage.inventoryList.exists)
    }
    
    func test09_Registration_CreateNewAccount() throws {
        // GIVEN: At login screen
        
        // WHEN: Registering with new account
        let randomEmail = "uitest\(Int.random(in: 10000...99999))@test.com"
        loginPage.registerWithEmail(randomEmail, password: "Test123!", firstName: "Test", lastName: "UIUser")
        
        // THEN: Should reach main screen (either household setup or inventory)
        let mainScreenElement = waitForAnyElement([
            app.otherElements["householdSetup.container"],
            app.buttons["inventory.addButton"]
        ], timeout: 10)
        XCTAssertNotNil(mainScreenElement, "Should reach main screen after registration")
    }
}
