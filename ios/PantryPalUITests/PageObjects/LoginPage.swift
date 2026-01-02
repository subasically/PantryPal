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
    
    // MARK: - Actions
    
    /// Complete login flow with email and password
    func loginWithEmail(_ email: String, password: String) {
        continueWithEmailButton.safeTap()
        
        emailField.tap()
        emailField.typeText(email)
        
        passwordField.tap()
        passwordField.typeText(password)
        
        loginButton.safeTap()
    }
    
    /// Register a new account
    func registerWithEmail(_ email: String, password: String, firstName: String, lastName: String) {
        continueWithEmailButton.safeTap()
        
        // Toggle to registration mode (if needed)
        let registerToggle = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'register'")).firstMatch
        if registerToggle.exists {
            registerToggle.tap()
        }
        
        if firstNameField.waitForExistence(timeout: 2) {
            firstNameField.tap()
            firstNameField.typeText(firstName)
            
            lastNameField.tap()
            lastNameField.typeText(lastName)
        }
        
        emailField.tap()
        emailField.typeText(email)
        
        passwordField.tap()
        passwordField.typeText(password)
        
        registerButton.safeTap()
    }
    
    // MARK: - Assertions
    
    func assertAtLoginScreen() {
        XCTAssertTrue(continueWithEmailButton.waitForExistence(timeout: 5), "Should be at login screen")
    }
}
