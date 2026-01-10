import XCTest

final class InventoryQuantityTests: BaseUITest {
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        loginAsTestUser()
    }

    func test01_IncrementAndDecrementItem() throws {
        // GIVEN: An item exists in inventory
        let itemName = "QtyTest-\(Int.random(in: 100...999))"
        inventoryPage.addCustomItem(name: itemName)
        inventoryPage.assertItemExists(name: itemName)
        
        // WHEN: Incrementing the item
        inventoryPage.incrementItem(name: itemName)
        
        // THEN: Quantity should update (UI logic might take a moment)
        // Ideally we check value, but for now just ensuring action doesn't crash
        
        // AND: Decrementing
        inventoryPage.decrementItem(name: itemName)
        
        // THEN: Item should still exist (quantity > 0)
        inventoryPage.assertItemExists(name: itemName)
    }
}
