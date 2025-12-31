import SwiftUI

@MainActor
class ConfettiCenter: ObservableObject {
    @Published var isActive = false
    
    private var activeTask: Task<Void, Never>?
    
    /// Triggers a confetti celebration for the specified duration
    func celebrate(duration: TimeInterval = 3.0) {
        // Cancel any existing celebration
        activeTask?.cancel()
        
        // Start new celebration
        isActive = true
        
        activeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            
            // Only deactivate if this task wasn't cancelled
            if !Task.isCancelled {
                isActive = false
            }
        }
    }
    
    /// Stop confetti immediately
    func stop() {
        activeTask?.cancel()
        activeTask = nil
        isActive = false
    }
}
