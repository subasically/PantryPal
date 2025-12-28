import Foundation
import SwiftData

@MainActor
final class ActionQueueService: Sendable {
    static let shared = ActionQueueService()
    
    private init() {}
    
    func processQueue(modelContext: ModelContext) async {
        // Fetch all pending actions sorted by creation date
        let descriptor = FetchDescriptor<SDPendingAction>(sortBy: [SortDescriptor(\.createdAt)])
        
        guard let actions = try? modelContext.fetch(descriptor), !actions.isEmpty else {
            return
        }
        
        print("Processing \(actions.count) pending actions...")
        
        for action in actions {
            do {
                try await sendAction(action)
                // If successful, delete from queue
                modelContext.delete(action)
                try? modelContext.save()
                print("Action \(action.type) processed successfully")
            } catch {
                print("Failed to process action \(action.type): \(error)")
                
                // Handle permanent errors (403 Forbidden - Limit Reached)
                if let apiError = error as? APIError, 
                   case .serverError(let msg) = apiError, 
                   msg.contains("limit reached") || msg.contains("Status 403") {
                    print("Action rejected by server (Limit Reached). Removing from queue.")
                    modelContext.delete(action)
                    try? modelContext.save()
                    
                    // Trigger Paywall
                    NotificationCenter.default.post(name: .showPaywall, object: nil)
                    
                    continue
                }
                
                action.retryCount += 1
                // If it's a permanent error (e.g. 400), maybe we should delete it or move to a "failed" queue?
                // For now, we just leave it to retry later (simple exponential backoff could be added)
                
                // Stop processing queue on error to preserve order dependency
                break
            }
        }
    }
    
    private func sendAction(_ action: SDPendingAction) async throws {
        guard let url = URL(string: "\(APIService.shared.currentBaseURL)\(action.endpoint)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = action.method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = APIService.shared.currentToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        if let payload = action.payload {
            request.httpBody = payload
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.noData
        }
        
        if httpResponse.statusCode >= 400 {
            // If 404 (Not Found) for a delete action, we can consider it success (idempotent)
            if httpResponse.statusCode == 404 && action.method == "DELETE" {
                return
            }
            
            // Try to parse error message
            if let errorResponse = try? JSONDecoder().decode([String: String].self, from: data),
               let errorMessage = errorResponse["error"] {
                throw APIError.serverError(errorMessage)
            }
            
            // Try to parse complex error response (like limit reached)
            struct ComplexError: Codable {
                let error: String
            }
            if let complexError = try? JSONDecoder().decode(ComplexError.self, from: data) {
                throw APIError.serverError(complexError.error)
            }
            
            throw APIError.serverError("Status \(httpResponse.statusCode)")
        }
    }
    
    func enqueue(context: ModelContext, type: SDPendingAction.ActionType, endpoint: String, method: String, body: (any Encodable)? = nil) {
        var payload: Data? = nil
        if let body = body {
            payload = try? JSONEncoder().encode(body)
        }
        
        let action = SDPendingAction(type: type, endpoint: endpoint, method: method, payload: payload)
        context.insert(action)
        try? context.save()
        
        // Trigger processing immediately (fire and forget)
        Task {
            await processQueue(modelContext: context)
        }
    }
}

extension Notification.Name {
    static let showPaywall = Notification.Name("showPaywall")
}
