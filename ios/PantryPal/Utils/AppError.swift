import Foundation

/// App-level error model with user-friendly messages
enum AppError: Error {
    case networkUnavailable
    case timeout
    case unauthorized
    case forbidden(reason: String? = nil)
    case validation(message: String)
    case serverUnavailable
    case rateLimited
    case decodeFailure
    case notFound(resource: String? = nil)
    case unknown
    
    /// User-facing message - always friendly and actionable
    var userMessage: String {
        switch self {
        case .networkUnavailable:
            return "No internet connection. Check your connection and try again."
        case .timeout:
            return "That took too long. Please try again."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        case .forbidden(let reason):
            if let reason = reason {
                return reason
            }
            return "You don't have permission to do that."
        case .validation(let message):
            return message
        case .serverUnavailable:
            return "PantryPal is having trouble right now. Please try again in a few moments."
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .decodeFailure:
            return "Something went wrong. Please try again."
        case .notFound(let resource):
            if let resource = resource {
                return "\(resource) not found."
            }
            return "That item couldn't be found."
        case .unknown:
            return "Something went wrong. Please try again."
        }
    }
    
    /// For logging purposes - includes technical context
    var technicalDescription: String {
        switch self {
        case .networkUnavailable:
            return "Network unavailable"
        case .timeout:
            return "Request timeout"
        case .unauthorized:
            return "Unauthorized (401)"
        case .forbidden(let reason):
            return "Forbidden (403): \(reason ?? "no reason")"
        case .validation(let message):
            return "Validation error: \(message)"
        case .serverUnavailable:
            return "Server unavailable (5xx)"
        case .rateLimited:
            return "Rate limited (429)"
        case .decodeFailure:
            return "JSON decoding failure"
        case .notFound(let resource):
            return "Not found (404): \(resource ?? "unknown")"
        case .unknown:
            return "Unknown error"
        }
    }
}

// MARK: - Error Extension for ViewModels
extension Error {
    /// Get user-friendly message from any error
    var userFriendlyMessage: String {
        if let appError = self as? AppError {
            return appError.userMessage
        }
        if let apiError = self as? APIError {
            return apiError.toAppError().userMessage
        }
        // Fallback
        return AppError.unknown.userMessage
    }
}
