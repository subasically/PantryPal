import XCTest

/// Base class for all UI tests with shared setup and helper methods
class BaseUITest: XCTestCase {
    
    var app: XCUIApplication!
    let server = TestServerClient()
    
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
        
        // 1. Reset & Seed Server (Deterministic state)
        // We ensure healthy first
        try? server.ensureHealthy() 
        server.reset()
        server.seed()
        
        // 2. Launch App
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launchEnvironment = [
            "API_BASE_URL": "http://localhost:3002/api",
            "UI_TEST_DISABLE_APP_LOCK": "true"
        ]
        
        app.launch()
        
        // 3. Handle System Alerts
        SystemAlertsHelper.dismissIfPresent(app: app)
    }
    
    override func tearDownWithError() throws {
        // We terminate the app to ensure clean state for next test
        // No need to sign out on UI level as we reset DB on next setup
        app.terminate()
        app = nil
    }
    
    // MARK: - Shared Helper Methods
    
    /// Login as the default test user (test@pantrypal.com)
    func loginAsTestUser() {
        // Check if we are already logged in (stale state) or at login screen
        let loginBtn = app.buttons["login.continueWithEmailButton"]
        
        // Short wait to see if login button appears
        if !loginBtn.waitForExistence(timeout: 5) {
            // If not at login screen, assume we might be logged in. 
            // Try to sign out to ensure clean state (since DB is reset)
            signOutIfLoggedIn()
        }

        loginPage.loginWithEmail("test@pantrypal.com", password: "Test123!")
        
        // Wait for splash screen to finish and main content to appear
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
    
    /// Navigate to a specific tab
    func navigateToTab(_ tabName: String) {
        let tabButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", tabName)).firstMatch
        XCTAssertTrue(tabButton.waitForExistence(timeout: 3), "Tab '\(tabName)' should exist")
        tabButton.safeTap()
    }
    
    /// Sign out if currently logged in (Helper for manual teardown if needed)
    func signOutIfLoggedIn() {
        // Check if we're already at login screen
        let loginBtn = app.buttons["login.continueWithEmailButton"]
        if loginBtn.exists {
            return // Already logged out
        }
        
        // Navigate to settings first - settings button is visible from all main screens
        let settingsBtn = app.buttons["settings.button"]
        if settingsBtn.waitForExistence(timeout: 2) {
            settingsBtn.tap()
            
            // Tap the Sign Out button in settings
            let signOutBtn = app.buttons["settings.signOutButton"]
            if signOutBtn.waitForExistence(timeout: 2) {
                signOutBtn.tap()
                
                // Wait for login screen to appear
                _ = loginBtn.waitForExistence(timeout: 5)
            }
        }
    }
}
