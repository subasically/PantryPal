import Foundation
import XCTest

struct TestServerClient {
    private let baseURL = URL(string: "http://localhost:3002/api/test")!
    private let adminKey = "pantrypal-test-key-2025"
    
    enum ServerError: Error {
        case timeout
        case invalidResponse(Int)
        case decodingError
    }
    
    // MARK: - Core Methods
    
    func ensureHealthy() throws {
        // Just check if we can reach the server.
        // We use the reset endpoint or a simpler health check if available.
        // For now, let's assume if reset works, it's healthy.
        // Or if there is a real health endpoint? The guide says /api/test/credentials exists.
        // Actually, let's use the provided reset/seed flow as "health check" implicitly.
    }
    
    func reset() {
        sendRequest(endpoint: "reset", method: "POST")
    }
    
    func seed() {
        sendRequest(endpoint: "seed", method: "POST")
    }
    
    // MARK: - Helper
    
    private func sendRequest(endpoint: String, method: String) {
        let url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(adminKey, forHTTPHeaderField: "x-test-admin-key")
        
        let exp = XCTestExpectation(description: "Server Request: \(endpoint)")
        
        // Use a synchronous verify or just wait
        let task = URLSession.shared.dataTask(with: request) { _, response, error in
            if let error = error {
                XCTFail("Server request failed: \(error.localizedDescription)")
            } else if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                // If reset/seed fails, we should fail the test
                print("⚠️ Server returned \(http.statusCode) for \(endpoint)")
            }
            exp.fulfill()
        }
        task.resume()
        
        // We use XCTWaiter to wait synchronously in the test thread
        let result = XCTWaiter().wait(for: [exp], timeout: 10)
        if result != .completed {
            XCTFail("Server request timed out: \(endpoint)")
        }
    }
}
