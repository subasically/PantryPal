import Foundation

enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case noData
    case decodingError(String)
    case serverError(String)
    case unauthorized
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .noData: return "No data received"
        case .decodingError(let message): return "Decoding error: \(message)"
        case .serverError(let message): return message
        case .unauthorized: return "Please log in again"
        case .networkError(let message): return "Network error: \(message)"
        }
    }
}

@MainActor
final class APIService: Sendable {
    static let shared = APIService()
    
    // Change this to your server IP when testing on device
    private var baseURL = "https://api-pantrypal.subasically.me/api"
    private var token: String?
    
    private init() {
        // Load token from keychain/userdefaults
        token = UserDefaults.standard.string(forKey: "authToken")
    }
    
    func setBaseURL(_ url: String) {
        baseURL = url
    }
    
    func setToken(_ newToken: String?) {
        token = newToken
        if let newToken = newToken {
            UserDefaults.standard.set(newToken, forKey: "authToken")
        } else {
            UserDefaults.standard.removeObject(forKey: "authToken")
        }
    }
    
    var isAuthenticated: Bool {
        token != nil
    }
    
    var currentToken: String? {
        token
    }
    
    var currentBaseURL: String {
        baseURL
    }
    
    // MARK: - Generic Request
    
    private func request<T: Decodable & Sendable>(
        endpoint: String,
        method: String = "GET",
        body: (any Encodable)? = nil
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        
        if httpResponse.statusCode == 401 {
            throw APIError.unauthorized
        }
        
        if httpResponse.statusCode >= 400 {
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorResponse["error"] {
                print("API Error (\(httpResponse.statusCode)): \(errorMessage)")
                throw APIError.serverError(errorMessage)
            }
            let responseString = String(data: data, encoding: .utf8) ?? "No data"
            print("API Error (\(httpResponse.statusCode)): \(responseString)")
            throw APIError.serverError("Request failed with status \(httpResponse.statusCode)")
        }
        
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decodingError(error.localizedDescription)
        }
    }
    
    // MARK: - Auth
    
    func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password)
        let response: AuthResponse = try await request(endpoint: "/auth/login", method: "POST", body: body)
        setToken(response.token)
        // Only seed if we have a household
        if response.user.householdId != nil {
            try? await seedDefaultLocations()
        }
        return response
    }
    
    func loginWithApple(identityToken: String, email: String?, name: PersonNameComponents?) async throws -> AuthResponse {
        struct AppleLoginRequest: Codable, Sendable {
            let identityToken: String
            let email: String?
            let name: PersonNameComponents?
            let householdName: String?
        }
        
        let body = AppleLoginRequest(
            identityToken: identityToken,
            email: email,
            name: name,
            householdName: nil
        )
        
        let response: AuthResponse = try await request(endpoint: "/auth/apple", method: "POST", body: body)
        setToken(response.token)
        if response.user.householdId != nil {
            try? await seedDefaultLocations()
        }
        return response
    }
    
    func register(email: String, password: String, name: String, householdName: String? = nil, householdId: String? = nil) async throws -> AuthResponse {
        let body = RegisterRequest(email: email, password: password, name: name, householdName: householdName, householdId: householdId)
        let response: AuthResponse = try await request(endpoint: "/auth/register", method: "POST", body: body)
        setToken(response.token)
        // Seed default locations for new households
        if response.user.householdId != nil {
            try? await seedDefaultLocations()
        }
        return response
    }
    
    func seedDefaultLocations() async throws {
        struct SeedResponse: Codable, Sendable {
            let message: String
            let seeded: Bool
        }
        let _: SeedResponse = try await request(endpoint: "/locations/seed-defaults", method: "POST")
    }
    
    func logout() {
        setToken(nil)
    }
    
    func getCurrentUser() async throws -> (User, Household?) {
        struct MeResponse: Codable, Sendable {
            let user: User
            let household: Household?
        }
        let response: MeResponse = try await request(endpoint: "/auth/me")
        return (response.user, response.household)
    }
    
    // MARK: - Products
    
    func lookupUPC(_ upc: String) async throws -> UPCLookupResponse {
        try await request(endpoint: "/products/lookup/\(upc)")
    }
    
    func createProduct(upc: String?, name: String, brand: String?, description: String?, category: String?) async throws -> Product {
        struct CreateProductRequest: Codable, Sendable {
            let upc: String?
            let name: String
            let brand: String?
            let description: String?
            let category: String?
        }
        let body = CreateProductRequest(upc: upc, name: name, brand: brand, description: description, category: category)
        return try await request(endpoint: "/products", method: "POST", body: body)
    }
    
    func getProducts() async throws -> [Product] {
        try await request(endpoint: "/products")
    }
    
    // MARK: - Inventory
    
    func getInventory() async throws -> [InventoryItem] {
        try await request(endpoint: "/inventory")
    }
    
    func getExpiringItems(days: Int = 7) async throws -> [InventoryItem] {
        try await request(endpoint: "/inventory/expiring?days=\(days)")
    }
    
    func getExpiredItems() async throws -> [InventoryItem] {
        try await request(endpoint: "/inventory/expired")
    }
    
    func quickAdd(upc: String, quantity: Int = 1, expirationDate: String? = nil, locationId: String) async throws -> QuickAddResponse {
        let body = QuickAddRequest(upc: upc, quantity: quantity, expirationDate: expirationDate, locationId: locationId)
        return try await request(endpoint: "/inventory/quick-add", method: "POST", body: body)
    }
    
    func addToInventory(productId: String, quantity: Int = 1, expirationDate: String? = nil, notes: String? = nil, locationId: String) async throws -> InventoryItem {
        struct AddRequest: Codable, Sendable {
            let productId: String
            let quantity: Int
            let expirationDate: String?
            let notes: String?
            let locationId: String
        }
        let body = AddRequest(productId: productId, quantity: quantity, expirationDate: expirationDate, notes: notes, locationId: locationId)
        return try await request(endpoint: "/inventory", method: "POST", body: body)
    }
    
    func updateInventoryItem(id: String, quantity: Int?, expirationDate: String?, notes: String?, locationId: String? = nil) async throws -> InventoryItem {
        struct UpdateRequest: Codable, Sendable {
            let quantity: Int?
            let expirationDate: String?
            let notes: String?
            let locationId: String?
        }
        let body = UpdateRequest(quantity: quantity, expirationDate: expirationDate, notes: notes, locationId: locationId)
        return try await request(endpoint: "/inventory/\(id)", method: "PUT", body: body)
    }
    
    func adjustQuantity(id: String, adjustment: Int) async throws -> AdjustQuantityResponse {
        let body = QuantityAdjustRequest(adjustment: adjustment)
        return try await request(endpoint: "/inventory/\(id)/quantity", method: "PATCH", body: body)
    }
    
    func deleteInventoryItem(id: String) async throws {
        struct DeleteResponse: Codable, Sendable {
            let success: Bool?
            let deleted: Bool?
        }
        let _: DeleteResponse = try await request(endpoint: "/inventory/\(id)", method: "DELETE")
    }
    
    // MARK: - Sync
    
    func fullSync() async throws -> FullSyncResponse {
        try await request(endpoint: "/sync/full")
    }
    
    // MARK: - Locations
    
    func getLocations() async throws -> [LocationFlat] {
        try await request(endpoint: "/locations/flat")
    }
    
    func getLocationsHierarchy() async throws -> LocationsResponse {
        try await request(endpoint: "/locations")
    }
    
    func createLocation(name: String, parentId: String? = nil) async throws -> Location {
        let body = CreateLocationRequest(name: name, parentId: parentId)
        return try await request(endpoint: "/locations", method: "POST", body: body)
    }
    
    func updateLocation(id: String, name: String) async throws -> Location {
        struct UpdateRequest: Codable, Sendable {
            let name: String
        }
        let body = UpdateRequest(name: name)
        return try await request(endpoint: "/locations/\(id)", method: "PUT", body: body)
    }
    
    func deleteLocation(id: String) async throws {
        struct DeleteResponse: Codable, Sendable {
            let success: Bool
            let message: String?
        }
        let _: DeleteResponse = try await request(endpoint: "/locations/\(id)", method: "DELETE")
    }
    
    // MARK: - Checkout
    
    func checkoutScan(upc: String) async throws -> CheckoutScanResponse {
        let body = CheckoutScanRequest(upc: upc)
        return try await request(endpoint: "/checkout/scan", method: "POST", body: body)
    }
    
    func getCheckoutHistory(limit: Int = 50, offset: Int = 0) async throws -> CheckoutHistoryResponse {
        try await request(endpoint: "/checkout/history?limit=\(limit)&offset=\(offset)")
    }
    
    // MARK: - Household Sharing
    
    func generateInviteCode() async throws -> InviteCodeResponse {
        try await request(endpoint: "/auth/household/invite", method: "POST")
    }
    
    func validateInviteCode(_ code: String) async throws -> InviteValidationResponse {
        try await request(endpoint: "/auth/household/invite/\(code)")
    }
    
    func joinHousehold(code: String) async throws -> JoinHouseholdResponse {
        struct JoinRequest: Codable, Sendable {
            let code: String
        }
        let body = JoinRequest(code: code)
        return try await request(endpoint: "/auth/household/join", method: "POST", body: body)
    }
    
    func createHousehold(name: String? = nil) async throws -> Household {
        struct CreateHouseholdRequest: Codable, Sendable {
            let name: String?
        }
        let body = CreateHouseholdRequest(name: name)
        return try await request(endpoint: "/auth/household", method: "POST", body: body)
    }
    
    func getHouseholdMembers() async throws -> HouseholdMembersResponse {
        try await request(endpoint: "/auth/household/members")
    }
    
    func getActiveInvites() async throws -> ActiveInvitesResponse {
        try await request(endpoint: "/auth/household/invites")
    }
    
    func resetHouseholdData() async throws {
        struct ResetResponse: Codable, Sendable {
            let success: Bool
            let message: String
        }
        let _: ResetResponse = try await request(endpoint: "/auth/household/data", method: "DELETE")
    }
}
