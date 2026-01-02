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
            "API_BASE_URL": "http://localhost:3002/api",
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
        
        // Wait for splash screen to finish and main content to appear (increased timeout for 2s splash + navigation)
        waitForMainScreen()
        skipOnboardingIfNeeded()
    }
    
    /// Skip onboarding if it appears
    func skipOnboardingIfNeeded() {
        let skipBtn = app.buttons["onboarding.skipButton"]
        if skipBtn.waitForExistence(timeout: 2) {
            skipBtn.safeTap()
            // Wait for inventory to appear after skipping
            _ = app.otherElements["inventory.list"].waitForExistence(timeout: 5)
        }
    }
    
    /// Wait for either household setup or inventory list to appear
    func waitForMainScreen() {
        // Wait longer for splash screen + navigation
        let householdSetup = app.otherElements["householdSetup.container"]
        let mainTab = app.otherElements["mainTab.container"]
        let inventoryList = app.otherElements["inventory.list"]
        
        // Try multiple ways to detect we're in the app
        let appeared = waitForAnyElement([householdSetup, mainTab, inventoryList], timeout: 15)
        XCTAssertNotNil(appeared, "Should reach main screen after login")
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
