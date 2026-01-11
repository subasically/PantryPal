import XCTest

/// Page object for the Inventory list screen
struct InventoryPage {
    let app: XCUIApplication
    
    // MARK: - Elements
    
    var inventoryList: XCUIElement {
        // Preference order for standard List
        let cv = app.collectionViews["inventory.list"]
        if cv.exists { return cv }
        
        let table = app.tables["inventory.list"]
        if table.exists { return table }
        
        // Return collection view as default if nothing exists yet (for waiting)
        // This ensures waitForExistence waits for the most likely type
        return cv
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
        // Return the CELL containing the named item, not just the text element
        inventoryList.cells.containing(.staticText, identifier: name).firstMatch
    }
    
    func incrementButton(id: String) -> XCUIElement {
        app.buttons["inventory.increment.\(id)"]
    }
    
    func decrementButton(id: String) -> XCUIElement {
        app.buttons["inventory.decrement.\(id)"]
    }
    
    // MARK: - Actions
    
    func waitForLoad() {
        // Check if we're at the inventory screen by looking for the add button
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Inventory screen should load (add button visible)")
    }
    
    func waitForLoaded() { waitForLoad() }
    
    func isAtInventoryScreen() -> Bool {
        return addButton.exists || inventoryList.exists
    }
    
    func openAddItem() {
        addButton.safeTap()
        XCTAssertTrue(app.textFields["addItem.nameField"].waitForExistence(timeout: 5), "Add item sheet should appear")
    }

    func addCustomItem(name: String, brand: String? = nil, quantity: Int? = nil) {
        openAddItem()
        
        let nameField = app.textFields["addItem.nameField"]
        nameField.tap()
        nameField.typeText(name)
        
        if let brand = brand {
            let brandField = app.textFields["addItem.brandField"]
            if brandField.exists {
                brandField.tap()
                brandField.typeText(brand)
            }
        }
        
        // Check for empty locations (blocker)
        if app.otherElements["addItem.emptyLocations"].exists {
            XCTFail("Cannot add item: No storage locations available. Seed data might be missing locations.")
        }
        
        let saveButton = app.buttons["addItem.saveButton"]
        
        // Dismiss keyboard if masking save button
        if !saveButton.isHittable {
            app.toolbars.buttons["Done"].tap()
        }
        
        XCTAssertTrue(saveButton.isEnabled, "Save button should be enabled after entering name")
        saveButton.tap()
        
        // Wait for sheet to dismiss and inventory to reload
        XCTAssertTrue(inventoryList.waitForExistence(timeout: 5), "Should return to inventory list")
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
    
    func incrementItem(name: String) {
        scrollToItem(name: name)
        let cell = itemCell(name: name)
        XCTAssertTrue(cell.exists, "Item '\(name)' not found to increment")
        
        // Use inclusive search for any increment button in this cell
        let btn = cell.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.increment.'")).firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 2), "Increment button not found for '\(name)'")
        btn.tap()
    }
    
    func decrementItem(name: String) {
        scrollToItem(name: name)
        let cell = itemCell(name: name)
        XCTAssertTrue(cell.exists, "Item '\(name)' not found to decrement")
        
        let btn = cell.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inventory.decrement.'")).firstMatch
        XCTAssertTrue(btn.waitForExistence(timeout: 2), "Decrement button not found for '\(name)'")
        btn.tap()
    }
    
    func decrementItem(id: String) {
        decrementButton(id: id).safeTap()
    }
    
    func pullToRefresh() {
        let start = inventoryList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        let end = inventoryList.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
        start.press(forDuration: 0, thenDragTo: end)
    }
    
    func scrollToItem(name: String) {
        let cell = itemCell(name: name)
        if cell.exists && cell.isHittable { return }
        
        // Swipe to find item
        var attempts = 0
        while !cell.exists && attempts < 5 {
            if inventoryList.exists {
                inventoryList.swipeUp()
            } else {
                app.swipeUp()
            }
            attempts += 1
        }
    }
    
    // MARK: - Assertions
    
    func assertItemExists(name: String) {
        scrollToItem(name: name)
        XCTAssertTrue(itemCell(name: name).waitForExistence(timeout: 3), "Item '\(name)' should exist")
    }
    
    func assertItemNotExists(name: String) {
        XCTAssertFalse(itemCell(name: name).exists, "Item '\(name)' should not exist")
    }
    
    func assertEmptyState() {
        XCTAssertTrue(emptyStateText.waitForExistence(timeout: 3), "Should show empty state")
    }
}
