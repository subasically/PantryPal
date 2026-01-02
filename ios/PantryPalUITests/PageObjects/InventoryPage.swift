import XCTest

/// Page object for the Inventory list screen
struct InventoryPage {
    let app: XCUIApplication
    
    // MARK: - Elements
    
    var inventoryList: XCUIElement {
        app.otherElements["inventory.list"]
    }
    
    var addButton: XCUIElement {
        app.buttons["inventory.addButton"]
    }
    
    var searchField: XCUIElement {
        app.searchFields.firstMatch
    }
    
    var emptyStateText: XCUIElement {
        app.staticTexts["No items in your pantry yet"]
    }
    
    func itemCell(name: String) -> XCUIElement {
        app.cells.staticTexts[name]
    }
    
    func incrementButton(id: String) -> XCUIElement {
        app.buttons["inventory.increment.\(id)"]
    }
    
    func decrementButton(id: String) -> XCUIElement {
        app.buttons["inventory.decrement.\(id)"]
    }
    
    // MARK: - Actions
    
    func waitForLoad() {
        XCTAssertTrue(inventoryList.waitForExistence(timeout: 5), "Inventory list should load")
    }
    
    func tapAddButton() {
        addButton.safeTap()
    }
    
    func searchFor(_ query: String) {
        searchField.tap()
        searchField.typeText(query)
    }
    
    func clearSearch() {
        let clearButton = searchField.buttons["Clear text"]
        if clearButton.exists {
            clearButton.tap()
        }
    }
    
    func incrementItem(id: String) {
        incrementButton(id: id).safeTap()
    }
    
    func decrementItem(id: String) {
        decrementButton(id: id).safeTap()
    }
    
    func pullToRefresh() {
        let start = inventoryList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = inventoryList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0, thenDragTo: end)
    }
    
    // MARK: - Assertions
    
    func assertItemExists(name: String) {
        XCTAssertTrue(itemCell(name: name).waitForExistence(timeout: 3), "Item '\(name)' should exist")
    }
    
    func assertItemNotExists(name: String) {
        XCTAssertFalse(itemCell(name: name).exists, "Item '\(name)' should not exist")
    }
    
    func assertEmptyState() {
        XCTAssertTrue(emptyStateText.waitForExistence(timeout: 3), "Should show empty state")
    }
}
