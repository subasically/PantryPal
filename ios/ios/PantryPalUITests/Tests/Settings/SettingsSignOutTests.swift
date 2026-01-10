// Refactored test for Settings Sign Out
//
// Tests:
// - Sign out flow

import XCTest

final class SettingsSignOutTests: BaseUITest {
    
    func test01_SignOut_Success() throws {
        // GIVEN: User is logged in
        loginAsTestUser()
        
        // WHEN: Tapping settings and signing out
        settingsPage.navigateToSettings()
        settingsPage.signOut()
        
        // THEN: Should be back at login screen
        XCTAssertTrue(loginPage.continueWithEmailButton.waitForExistence(timeout: 5), "Should return to login screen")
    }
}
