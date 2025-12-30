import SwiftUI
import Combine

/// Centralized toast message system
/// All toasts are queued and displayed globally at the top of the app
@MainActor
class ToastCenter: ObservableObject {
    static let shared = ToastCenter()
    
    @Published private(set) var toasts: [Toast] = []
    
    private var timers: [UUID: Task<Void, Never>] = [:]
    
    private init() {}
    
    /// Show a toast message
    /// - Parameters:
    ///   - message: The message to display
    ///   - type: The toast type (success, info, warning, error)
    ///   - duration: How long to show the toast (default: 2.5s for success/info, 4.5s for error/warning)
    func show(_ message: String, type: ToastType, duration: TimeInterval? = nil) {
        let defaultDuration = type == .error || type == .warning ? 4.5 : 2.5
        let finalDuration = duration ?? defaultDuration
        
        let toast = Toast(
            message: message,
            type: type,
            duration: finalDuration
        )
        
        // Add to queue
        toasts.append(toast)
        
        // Trigger haptic
        triggerHaptic(for: type)
        
        // Schedule auto-dismiss
        let task = Task {
            try? await Task.sleep(nanoseconds: UInt64(finalDuration * 1_000_000_000))
            dismiss(toast.id)
        }
        
        timers[toast.id] = task
    }
    
    /// Dismiss a specific toast
    func dismiss(_ id: UUID) {
        timers[id]?.cancel()
        timers.removeValue(forKey: id)
        
        withAnimation(.easeOut(duration: 0.3)) {
            toasts.removeAll { $0.id == id }
        }
    }
    
    /// Clear all toasts
    func dismissAll() {
        timers.values.forEach { $0.cancel() }
        timers.removeAll()
        
        withAnimation(.easeOut(duration: 0.3)) {
            toasts.removeAll()
        }
    }
    
    private func triggerHaptic(for type: ToastType) {
        let generator = UINotificationFeedbackGenerator()
        switch type {
        case .success:
            generator.notificationOccurred(.success)
        case .error:
            generator.notificationOccurred(.error)
        case .warning:
            generator.notificationOccurred(.warning)
        case .info:
            break // No haptic for info
        }
    }
}

// MARK: - Toast Model

struct Toast: Identifiable, Equatable {
    let id: UUID
    let message: String
    let type: ToastType
    let duration: TimeInterval
    let createdAt: Date
    
    init(message: String, type: ToastType, duration: TimeInterval) {
        self.id = UUID()
        self.message = message
        self.type = type
        self.duration = duration
        self.createdAt = Date()
    }
}

// MARK: - Toast Type

enum ToastType {
    case success
    case info
    case warning
    case error
    
    var color: Color {
        switch self {
        case .success: return .ppGreen
        case .info: return .ppPurple
        case .warning: return Color.orange
        case .error: return .ppDanger
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}
