import XCTest

final class DeleteHouseholdDataTests: BaseUITest {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        loginPage.waitForLoaded()
        // Ensure we are logged in as test user
        loginAsTestUser()
        
        // Ensure we are on inventory tab
        inventoryPage.waitForLoaded()
    }
    
    /// Test that deleting household data clears all inventory and grocery items
    func testDeleteHouseholdDataClearsAllData() throws {
        // 1. Add some test items via InventoryPage
        let item1 = "DelMilk-\(Int.random(in: 100...999))"
        let item2 = "DelBread-\(Int.random(in: 100...999))"
        
        inventoryPage.addCustomItem(name: item1, quantity: 2)
        inventoryPage.addCustomItem(name: item2, quantity: 1)
        
        // 2. Verify items exist
        inventoryPage.assertItemExists(name: item1)
        inventoryPage.assertItemExists(name: item2)
        
        // 3. Navigate to Settings
        let settingsButton = app.buttons["settings.button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5), "Settings button should be visible")
        settingsButton.tap()
        
        // 4. Find Delete Household Data button (might need scrolling)
        let deleteButton = app.buttons["Delete Household Data"]
        if !deleteButton.exists {
            app.swipeUp() // Scroll down
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 3), "Delete button not found")
        deleteButton.tap()
        
        // 5. Confirm first alert
        let deleteAlert = app.alerts["Delete Household Data?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 3))
        deleteAlert.buttons["Continue"].tap()
        
        // 6. Enter verification text in second alert
        let verifyAlert = app.alerts["Verify Reset"]
        XCTAssertTrue(verifyAlert.waitForExistence(timeout: 3))
        
        let textField = verifyAlert.textFields.firstMatch
        XCTAssertTrue(textField.waitForExistence(timeout: 2))
        textField.tap()
        textField.typeText("RESET")
        
        verifyAlert.buttons["Delete"].tap()
        
        // 7. Wait for deletion to complete and Settings to dismiss
        // The app dismisses Settings automatically on success, revealing Inventory
        let emptyState = app.staticTexts["No items in your pantry"]
        XCTAssertTrue(emptyState.waitForExistence(timeout: 10), "Should show empty state after deletion")
        
        // 8. Verify specific items are gone
        XCTAssertFalse(inventoryPage.itemCell(name: item1).exists, "Item 1 should be deleted")
        XCTAssertFalse(inventoryPage.itemCell(name: item2).exists, "Item 2 should be deleted")
    }
    
    /// Test that canceling the delete operation preserves data
    func testCancelDeletePreservesData() throws {
        // 1. Add item
        let item = "KeepMe-\(Int.random(in: 100...999))"
        inventoryPage.addCustomItem(name: item)
        inventoryPage.assertItemExists(name: item)
        
        // 2. Navigate to Settings -> Delete
        let settingsButton = app.buttons["settings.button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        
        let deleteButton = app.buttons["Delete Household Data"]
        if !deleteButton.exists {
            app.swipeUp()
            app.swipeUp()
        }
        deleteButton.tap()
        
        // 3. Cancel first alert
        let deleteAlert = app.alerts["Delete Household Data?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 3))
        deleteAlert.buttons["Cancel"].tap()
        
        // 4. Close Settings
        let doneButton = app.buttons["Done"]
        if doneButton.exists {
            doneButton.tap()
        }
        
        // 5. Verify item still exists
        inventoryPage.scrollToItem(name: item)
        inventoryPage.assertItemExists(name: item)
    }
    
    /// Test that wrong verification text prevents deletion
    func testWrongVerificationTextPreventsDeletion() throws {
        // 1. Add item
        let item = "Safe-\(Int.random(in: 100...999))"
        inventoryPage.addCustomItem(name: item)
        inventoryPage.assertItemExists(name: item)
        
        // 2. Settings -> Delete -> Continue
        let settingsButton = app.buttons["settings.button"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()
        
        let deleteButton = app.buttons["Delete Household Data"]
        if !deleteButton.exists {
            app.swipeUp()
            app.swipeUp()
        }
        deleteButton.tap()
        
        let deleteAlert = app.alerts["Delete Household Data?"]
        XCTAssertTrue(deleteAlert.waitForExistence(timeout: 3))
        deleteAlert.buttons["Continue"].tap()
        
        // 3. Wrong text in second alert
        let verifyAlert = app.alerts["Verify Reset"]
        XCTAssertTrue(verifyAlert.waitForExistence(timeout: 3))
        
        let textField = verifyAlert.textFields.firstMatch
        textField.tap()
        textField.typeText("WRONG")
        
        // 4. Attempt Delete (should allow tap but fail action)
        let deleteActionBtn = verifyAlert.buttons["Delete"]
        if deleteActionBtn.isEnabled {
             deleteActionBtn.tap()
        }
        
        // 5. Cancel out
        verifyAlert.buttons["Cancel"].tap()
        
        // 6. Close Settings
        let doneButton = app.buttons["Done"]
        if doneButton.exists {
            doneButton.tap()
        }
        
        // 7. Verify item still exists
        inventoryPage.scrollToItem(name: item)
        inventoryPage.assertItemExists(name: item)
    }
}
