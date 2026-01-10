import XCTest

/// Page object for the Settings screen
struct SettingsPage {
    let app: XCUIApplication
    
    // MARK: - Elements
    
    var settingsNavBar: XCUIElement {
        app.navigationBars["Settings"]
    }
    
    var accountHeader: XCUIElement {
        app.staticTexts["Account"]
    }
    
    var settingsList: XCUIElement {
        app.collectionViews["settings.list"]
    }
    
    var signOutButton: XCUIElement {
        app.buttons["settings.signOutButton"]
    }
    
    var deleteHouseholdDataButton: XCUIElement {
        app.buttons["Delete Household Data"]
    }
    
    var settingsButton: XCUIElement {
        app.buttons["settings.button"]
    }
    
    // MARK: - Actions
    
    func openSettings() {
        settingsButton.safeTap()
    }
    
    func signOut() {
        // Scroll to find sign out button if needed
        var attempts = 0
        while !signOutButton.exists && attempts < 5 {
            // Try swiping the list if found, otherwise general swipe
            if settingsList.exists {
                settingsList.swipeUp()
            } else {
                app.swipeUp()
            }
            attempts += 1
        }
        
        signOutButton.safeTap()
        
        // Wait for login screen to appear
        let loginBtn = app.buttons["login.continueWithEmailButton"]
        _ = loginBtn.waitForExistence(timeout: 5)
    }
    
    func deleteHouseholdData() {
        // Scroll to find delete button if needed
        var attempts = 0
        while !deleteHouseholdDataButton.exists && attempts < 5 {
            if settingsList.exists {
                settingsList.swipeUp()
            } else {
                app.swipeUp()
            }
            attempts += 1
        }
        
        deleteHouseholdDataButton.safeTap()
        
        // Handle first confirmation alert
        let continueBtn = app.alerts.buttons["Continue"]
        if continueBtn.waitForExistence(timeout: 2) {
            continueBtn.tap()
        }
        
        // Handle verification alert
        let verifyAlert = app.alerts["Verify Reset"]
        if verifyAlert.waitForExistence(timeout: 2) {
            let textField = verifyAlert.textFields.firstMatch
            if textField.waitForExistence(timeout: 2) {
                textField.tap()
                textField.typeText("RESET")
                verifyAlert.buttons["Delete"].tap()
            }
        }
    }
    
    // MARK: - Assertions
    
    func assertAtSettings() {
        // Check for navigation bar or the first section
        XCTAssertTrue(settingsNavBar.waitForExistence(timeout: 5) || accountHeader.waitForExistence(timeout: 5), "Should be at settings screen")
    }
}
