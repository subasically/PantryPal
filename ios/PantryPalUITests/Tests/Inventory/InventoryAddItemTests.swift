import XCTest

final class InventoryAddItemTests: BaseUITest {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        // Ensure we end up on the main screen (Inventory)
        loginAsTestUser()
    }

    func test01_AddCustomItem_Success() throws {
        // GIVEN: We are on the inventory screen
        XCTAssertTrue(inventoryPage.isAtInventoryScreen(), "Should be at inventory screen")
        
        let itemName = "Test Banana \(Int.random(in: 100...999))"
        
        // WHEN: We add a custom item
        inventoryPage.addCustomItem(name: itemName)
        
        // THEN: The item should appear in the list
        // Note: Sometimes sync/add takes a moment, verify existence with wait
        inventoryPage.assertItemExists(name: itemName)
    }
}
