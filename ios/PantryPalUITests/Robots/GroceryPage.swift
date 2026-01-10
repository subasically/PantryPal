import XCTest

/// Page object for the Grocery list screen
struct GroceryPage {
    let app: XCUIApplication
    
    // MARK: - Elements
    
    var groceryTab: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'grocery'")).firstMatch
    }
    
    var addField: XCUIElement {
        app.textFields["grocery.addField"]
    }
    
    var emptyStateText: XCUIElement {
        app.staticTexts["Your grocery list is empty"]
    }
    
    func itemCell(name: String) -> XCUIElement {
        app.cells.staticTexts[name]
    }
    
    // MARK: - Actions
    
    func navigateToGrocery() {
        groceryTab.safeTap()
    }
    
    func addItem(name: String) {
        addField.tap()
        addField.typeText(name)
        app.keyboards.buttons["Return"].tap()
    }
    
    // MARK: - Assertions
    
    func assertItemExists(name: String) {
        XCTAssertTrue(itemCell(name: name).waitForExistence(timeout: 3), "Grocery item '\(name)' should exist")
    }
    
    func assertItemNotExists(name: String) {
        XCTAssertFalse(itemCell(name: name).exists, "Grocery item '\(name)' should not exist")
    }
    
    func assertEmptyState() {
        XCTAssertTrue(emptyStateText.waitForExistence(timeout: 3), "Should show empty grocery state")
    }
}
