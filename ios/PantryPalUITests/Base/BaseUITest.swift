import XCTest

/// Base class for all UI tests with shared setup and helper methods
class BaseUITest: XCTestCase {
    
    var app: XCUIApplication!
    
    // MARK: - Page Objects (Lazy accessors)
    
    var loginPage: LoginPage {
        LoginPage(app: app)
    }
    
    var inventoryPage: InventoryPage {
        InventoryPage(app: app)
    }
    
    var settingsPage: SettingsPage {
        SettingsPage(app: app)
    }
    
    var groceryPage: GroceryPage {
        GroceryPage(app: app)
    }
    
    // MARK: - Setup & Teardown
    
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
    
    // MARK: - Shared Helper Methods
    
    /// Login as the default test user (test@pantrypal.com)
    func loginAsTestUser() {
        loginPage.loginWithEmail("test@pantrypal.com", password: "Test123!")
        skipOnboardingIfNeeded()
        waitForMainScreen()
    }
    
    /// Skip onboarding if it appears
    func skipOnboardingIfNeeded() {
        let skipBtn = app.buttons["onboarding.skipButton"]
        if skipBtn.waitForExistence(timeout: 2) {
            skipBtn.safeTap()
        }
    }
    
    /// Wait for either household setup or inventory list to appear
    func waitForMainScreen() {
        let householdSetup = app.otherElements["householdSetup.container"]
        let inventoryList = app.otherElements["inventory.list"]
        let mainTab = app.otherElements["mainTab.container"]
        
        let appeared = waitForAnyElement([householdSetup, inventoryList, mainTab], timeout: 8)
        XCTAssertNotNil(appeared, "Should reach main screen after login")
        
        // If household setup, skip it
        if householdSetup.exists {
            let skipBtn = app.buttons["onboarding.skipButton"]
            if skipBtn.exists {
                skipBtn.safeTap()
            }
        }
        
        // Final wait for inventory
        _ = inventoryList.waitForExistence(timeout: 3)
    }
    
    /// Sign out if currently logged in
    func signOutIfLoggedIn() {
        let settingsBtn = app.buttons["settings.button"]
        if settingsBtn.waitForExistence(timeout: 2) {
            settingsBtn.tap()
            
            let signOutBtn = app.buttons["settings.signOutButton"]
            if signOutBtn.waitForExistence(timeout: 2) {
                signOutBtn.tap()
            }
        }
    }
    
    /// Navigate to a specific tab
    func navigateToTab(_ tabName: String) {
        let tabButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", tabName)).firstMatch
        XCTAssertTrue(tabButton.waitForExistence(timeout: 3), "Tab '\(tabName)' should exist")
        tabButton.safeTap()
    }
}
