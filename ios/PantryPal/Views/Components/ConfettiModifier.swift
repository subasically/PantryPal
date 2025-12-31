import SwiftUI

struct ConfettiModifier: ViewModifier {
    @EnvironmentObject private var confettiCenter: ConfettiCenter
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if confettiCenter.isActive {
                ConfettiOverlay()
                    .zIndex(999)
            }
        }
    }
}

extension View {
    func withConfetti() -> some View {
        modifier(ConfettiModifier())
    }
}
