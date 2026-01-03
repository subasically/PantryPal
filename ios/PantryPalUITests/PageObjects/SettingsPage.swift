import XCTest

/// Page object for the Settings screen
struct SettingsPage {
    let app: XCUIApplication
    
    // MARK: - Elements
    
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
        signOutButton.safeTap()
        
        // Wait for login screen to appear
        let loginBtn = app.buttons["login.continueWithEmailButton"]
        _ = loginBtn.waitForExistence(timeout: 5)
    }
    
    func deleteHouseholdData() {
        // Scroll to find delete button if needed
        if !deleteHouseholdDataButton.exists {
            app.swipeUp()
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
            textField.tap()
            textField.typeText("RESET")
            
            verifyAlert.buttons["Delete"].tap()
        }
    }
    
    // MARK: - Assertions
    
    func assertAtSettings() {
        XCTAssertTrue(signOutButton.waitForExistence(timeout: 3), "Should be at settings screen")
    }
}
