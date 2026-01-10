import XCTest

/// Page object for the Login/Registration screen
struct LoginPage {
    let app: XCUIApplication
    
    // MARK: - Elements
    
    var continueWithEmailButton: XCUIElement {
        app.buttons["login.continueWithEmailButton"]
    }
    
    var emailField: XCUIElement {
        app.textFields["login.emailField"]
    }
    
    var passwordField: XCUIElement {
        app.secureTextFields["login.passwordField"]
    }
    
    var loginButton: XCUIElement {
        app.buttons["login.loginButton"]
    }
    
    var registerButton: XCUIElement {
        app.buttons["login.registerButton"]
    }
    
    var firstNameField: XCUIElement {
        app.textFields["login.firstNameField"]
    }
    
    var lastNameField: XCUIElement {
        app.textFields["login.lastNameField"]
    }
    
    var toggleModeButton: XCUIElement {
        // The button that switches between Login and Register modes
        // Usually labeled "Register" (in Login mode) or "Login" (in Register mode)
        // If we need a stable ID, we should add one, but relying on label is common for toggles
        // Assuming "Register" if trying to register, "Login" if trying to login
        app.buttons["login.toggleModeButton"]
    }
    
    // MARK: - Actions
    
    func waitForLoaded() {
        XCTAssertTrue(continueWithEmailButton.waitForExistence(timeout: 5), "Login landing page not loaded")
    }
    
    func tapContinueWithEmail() {
        continueWithEmailButton.safeTap()
        _ = emailField.waitForExistence(timeout: 3)
    }
    
    func enterEmail(_ email: String) {
        emailField.tap()
        // Clear text if needed? Usually empty on fresh launch
        emailField.typeText(email)
    }
    
    func enterPassword(_ password: String) {
        passwordField.tap()
        // Secure fields can be tricky; sometimes need double tap or wait for focus
        // safeTap usually handles hittable check
        passwordField.typeText(password)
    }
    
    func tapLogin() {
        loginButton.safeTap()
    }
    
    func tapRegister() {
        registerButton.safeTap()
    }
    
    /// Complete login flow with email and password
    func loginWithEmail(_ email: String, password: String) {
        // If we are at the landing page, tap continue first
        if continueWithEmailButton.exists {
            tapContinueWithEmail()
        }
        
        enterEmail(email)
        enterPassword(password)
        tapLogin()
    }
    
    /// Register a new account
    func registerWithEmail(_ email: String, password: String, firstName: String, lastName: String) {
        if continueWithEmailButton.exists {
             tapContinueWithEmail()
        }
        
        // Wait for email form to appear
        _ = emailField.waitForExistence(timeout: 3)
        
        // Toggle to registration mode if needed
        // Identify if we are in login mode (Login button exists) or Register mode
        // If login button exists, and we want to register, we need to toggle
        if loginButton.exists && !registerButton.exists {
            // Find the toggle button. It might be labeled "Register"
            let toggle = app.buttons["Register"]
            if toggle.exists {
                toggle.tap()
            }
        }
        
        // Wait for name fields to appear after toggling to registration
        if firstNameField.waitForExistence(timeout: 2) {
            firstNameField.tap()
            firstNameField.typeText(firstName)
            
            lastNameField.tap()
            lastNameField.typeText(lastName)
        }
        
        enterEmail(email)
        enterPassword(password)
        tapRegister()
    }
    
    // MARK: - Assertions
    
    func assertAtLoginScreen() {
        XCTAssertTrue(continueWithEmailButton.waitForExistence(timeout: 5), "Should be at login screen")
    }
    
    func assertErrorVisible(text: String) {
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 3) {
            XCTAssertTrue(alert.staticTexts[text].exists || alert.label.contains(text))
            // Dismiss it so test can continue?
            // alert.buttons["OK"].tap()
        } else {
             // Maybe it's a text element
             XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 3))
        }
    }
}
