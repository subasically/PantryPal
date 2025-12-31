import Foundation

/// Centralized logging utility for debugging
struct AppLogger {
    
    /// Log an API error with full technical details
    static func logAPIError(
        endpoint: String,
        method: String = "GET",
        statusCode: Int? = nil,
        responseBody: String? = nil,
        underlyingError: Error? = nil
    ) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔴 API ERROR")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Endpoint: \(method) \(endpoint)")
        
        if let statusCode = statusCode {
            print("📊 Status: \(statusCode)")
        }
        
        if let body = responseBody {
            let truncated = body.count > 500 ? String(body.prefix(500)) + "..." : body
            print("📦 Response: \(truncated)")
        }
        
        if let error = underlyingError {
            print("⚠️ Underlying: \(error.localizedDescription)")
            print("   Type: \(type(of: error))")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        #else
        // In production, log minimal safe info only
        print("API Error: \(endpoint) - Status: \(statusCode ?? 0)")
        #endif
    }
    
    /// Log a decoding error with context
    static func logDecodingError(
        endpoint: String,
        expectedType: String,
        responseData: Data?,
        error: Error
    ) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🔴 DECODING ERROR")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Endpoint: \(endpoint)")
        print("🎯 Expected: \(expectedType)")
        print("⚠️ Error: \(error.localizedDescription)")
        
        if let data = responseData, let responseString = String(data: data, encoding: .utf8) {
            let truncated = responseString.count > 500 ? String(responseString.prefix(500)) + "..." : responseString
            print("📦 Raw Response: \(truncated)")
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        #endif
    }
    
    /// Log a general app error
    static func logError(
        _ error: AppError,
        context: String? = nil,
        additionalInfo: [String: Any]? = nil
    ) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("⚠️ APP ERROR")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        if let context = context {
            print("📍 Context: \(context)")
        }
        print("🔧 Technical: \(error.technicalDescription)")
        print("👤 User Message: \(error.userMessage)")
        
        if let info = additionalInfo {
            print("ℹ️ Additional Info:")
            for (key, value) in info {
                print("   \(key): \(value)")
            }
        }
        
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        #endif
    }
    
    /// Log network errors
    static func logNetworkError(_ error: URLError, endpoint: String) {
        #if DEBUG
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("🌐 NETWORK ERROR")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        print("📍 Endpoint: \(endpoint)")
        print("🔢 Code: \(error.code.rawValue)")
        print("📝 Description: \(error.localizedDescription)")
        print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
        #endif
    }
}
