import Foundation
import SwiftData

@Model
final class SDPendingAction {
    var id: UUID
    var type: ActionType
    var endpoint: String
    var method: String
    var payload: Data?
    var createdAt: Date
    var retryCount: Int
    
    init(type: ActionType, endpoint: String, method: String, payload: Data? = nil) {
        self.id = UUID()
        self.type = type
        self.endpoint = endpoint
        self.method = method
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
    }
    
    enum ActionType: String, Codable {
        case create
        case update
        case delete
        case checkout
        case quickAdd
    }
}
