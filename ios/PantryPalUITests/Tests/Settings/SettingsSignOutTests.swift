import XCTest

final class SettingsSignOutTests: BaseUITest {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        loginAsTestUser()
    }

    func test01_SignOut_Success() throws {
        // GIVEN: User is logged in (handled by setup)
        
        // WHEN: We open settings
        settingsPage.openSettings()
        settingsPage.assertAtSettings()
        
        // AND: Sign out
        settingsPage.signOut()
        
        // THEN: Should return to login screen
        loginPage.assertAtLoginScreen()
    }
}
