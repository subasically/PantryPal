import XCTest

struct MainTabPage {
    let app: XCUIApplication
    
    // MARK: - Elements
    
    var tabBar: XCUIElement {
        app.tabBars.firstMatch
    }
    
    var inventoryTab: XCUIElement {
        app.buttons["mainTab.inventoryTab"] // Assuming ID exists, or use label
    }
    
    var groceryTab: XCUIElement {
        app.buttons["mainTab.groceryTab"]
    }
    
    // MARK: - Assertions
    
    func waitForLoaded() {
        // We consider the main tab loaded if the inventory list OR the empty state is visible
        // OR if the Tab Bar itself is visible
        XCTAssertTrue(tabBar.waitForExistence(timeout: 10), "Tab bar should be visible on Main Screen")
    }
    
    func assertLoggedIn() {
        waitForLoaded()
        // verify we are not on login screen
        XCTAssertFalse(app.buttons["login.continueWithEmailButton"].exists)
    }
}
