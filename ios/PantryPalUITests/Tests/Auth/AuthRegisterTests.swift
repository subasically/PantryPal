import XCTest

final class AuthRegisterTests: BaseUITest {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        loginPage.waitForLoaded()
    }

    func test01_RegisterWithEmail_Success_NavigatesToMain() throws {
        // GIVEN: On login screen
        
        // WHEN: Registering with new user
        let email = "newuser\(Int.random(in: 1000...9999))@test.com"
        loginPage.registerWithEmail(email, password: "Password123!", firstName: "New", lastName: "Tester")
        
        // THEN: Should navigate to main app (or household setup if no invite)
        // Since seed logic usually creates a clean DB, a new user might need to setup household.
        // If your test suite auto-joins household, check that.
        // Assuming user lands on Household Setup or Main Tab.
        
        let householdSetup = app.otherElements["householdSetup.container"]
        let mainTab = app.tabBars.firstMatch
        
        // Wait for either
        let joined = waitForAnyElement([householdSetup, mainTab], timeout: 10)
        XCTAssertNotNil(joined, "Should have navigated past login")
        
        if householdSetup.exists {
             // Handle setup flow if needed for this test to be "Complete"
             // Or just assert we reached it.
             print("Reached Household Setup")
        } else {
             print("Reached Main Tab")
        }
    }
}
