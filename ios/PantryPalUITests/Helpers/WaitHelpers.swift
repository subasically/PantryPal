import XCTest

// MARK: - XCUIElement Extensions

extension XCUIElement {
    /// Wait for element to exist and be hittable (tappable)
    /// - Parameter timeout: Maximum time to wait in seconds
    /// - Returns: True if element becomes hittable within timeout
    func waitForHittable(timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    /// Tap element only when it's hittable (replaces tap + sleep pattern)
    /// - Parameter timeout: Maximum time to wait before asserting
    func safeTap(timeout: TimeInterval = 5) {
        XCTAssertTrue(waitForHittable(timeout: timeout), "Element not tappable: \(self.debugDescription)")
        tap()
    }
    
    /// Wait for element to disappear (useful for loading indicators)
    /// - Parameter timeout: Maximum time to wait in seconds
    /// - Returns: True if element disappears within timeout
    func waitForDisappearance(timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}

// MARK: - XCTestCase Extensions

extension XCTestCase {
    /// Wait for any of the provided elements to appear
    /// - Parameters:
    ///   - elements: Array of elements to wait for
    ///   - timeout: Maximum time to wait
    /// - Returns: The first element that appears, or nil if timeout
    func waitForAnyElement(_ elements: [XCUIElement], timeout: TimeInterval = 5) -> XCUIElement? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            for element in elements {
                if element.exists {
                    return element
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        }
        return nil
    }
    
    /// Wait for element to exist with better error messaging
    /// - Parameters:
    ///   - element: Element to wait for
    ///   - timeout: Maximum time to wait
    ///   - message: Custom error message
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5, message: String? = nil) -> Bool {
        let exists = element.waitForExistence(timeout: timeout)
        if !exists {
            let errorMsg = message ?? "Element not found: \(element.debugDescription)"
            XCTFail(errorMsg)
        }
        return exists
    }
}
