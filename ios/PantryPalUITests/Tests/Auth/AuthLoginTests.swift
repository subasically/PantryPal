import XCTest

final class AuthLoginTests: BaseUITest {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Ensure we are at login screen for each test
        // Resetting DB in super.setUp() puts us in fresh state, which usually means Login Screen
        loginPage.waitForLoaded()
    }

    func test01_LoginWithEmail_Success() throws {
        // GIVEN: We are on the login screen (asserted in setUp)
        
        // WHEN: We login with valid credentials (matches seed data)
        loginPage.loginWithEmail("test@pantrypal.com", password: "Test123!")
        
        // THEN: We should be navigated to the main app
        MainTabPage(app: app).assertLoggedIn()
    }
    
    // Dependent on UI implementation of error handling
    func test02_LoginWithEmail_InvalidPassword_ShowsError() throws {
        // GIVEN: On login screen
        
        // WHEN: Login with wrong password
        loginPage.loginWithEmail("test@pantrypal.com", password: "WrongPassword")
        
        // THEN: Alert or error message should appear
        // "Invalid email or password" is standard
        loginPage.assertErrorVisible(text: "Invalid credentials")
        
        // AND: Still on login screen (or dismissed alert)
        // Check login button still exists
        XCTAssertTrue(loginPage.loginButton.exists)
    }
}
