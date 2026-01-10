import Foundation

/// Maps technical errors to user-friendly AppError
struct AppErrorMapper {
    
    /// Convert URLError to AppError
    static func map(_ urlError: URLError, endpoint: String) -> AppError {
        AppLogger.logNetworkError(urlError, endpoint: endpoint)
        
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            return .networkUnavailable
        case .timedOut:
            return .timeout
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return .serverUnavailable
        default:
            return .unknown
        }
    }
    
    /// Convert HTTP status code to AppError
    static func map(statusCode: Int, endpoint: String, method: String = "GET", serverMessage: String? = nil, responseBody: String? = nil) -> AppError {
        AppLogger.logAPIError(
            endpoint: endpoint,
            method: method,
            statusCode: statusCode,
            responseBody: responseBody
        )
        
        switch statusCode {
        case 400:
            // Check for specific validation messages
            if let message = serverMessage, !message.isEmpty {
                return .validation(message: message)
            }
            return .validation(message: "Invalid request. Please check your input.")
            
        case 401:
            // Check for specific error message (e.g. from Login)
            if let message = serverMessage, !message.isEmpty {
                return .validation(message: message)
            }
            return .unauthorized
            
        case 403:
            // Check for premium-related messages
            if let message = serverMessage, message.contains("Premium") {
                return .forbidden(reason: "This feature requires Premium.")
            }
            return .forbidden(reason: serverMessage)
            
        case 404:
            return .notFound(resource: serverMessage)
            
        case 429:
            return .rateLimited
            
        case 500...599:
            return .serverUnavailable
            
        default:
            return .unknown
        }
    }
    
    /// Convert decoding error to AppError
    static func mapDecodingError(
        endpoint: String,
        expectedType: String,
        responseData: Data?,
        error: Error
    ) -> AppError {
        AppLogger.logDecodingError(
            endpoint: endpoint,
            expectedType: expectedType,
            responseData: responseData,
            error: error
        )
        return .decodeFailure
    }
    
    /// Convert generic Error to AppError
    static func map(_ error: Error, endpoint: String, context: String? = nil) -> AppError {
        // Check if it's already an AppError
        if let appError = error as? AppError {
            AppLogger.logError(appError, context: context)
            return appError
        }
        
        // Check if it's a URLError
        if let urlError = error as? URLError {
            return map(urlError, endpoint: endpoint)
        }
        
        // Log and return unknown
        AppLogger.logAPIError(
            endpoint: endpoint,
            underlyingError: error
        )
        return .unknown
    }
}
