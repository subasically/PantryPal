import SwiftUI

/// Global toast host view that displays all active toasts
/// Place this at the app root level to show toasts from anywhere
struct ToastHostView: View {
    @StateObject private var toastCenter = ToastCenter.shared
    
    var body: some View {
        VStack(spacing: 8) {
            ForEach(toastCenter.toasts) { toast in
                ToastCard(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture {
                        toastCenter.dismiss(toast.id)
                    }
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: toastCenter.toasts.count)
    }
}

/// Individual toast card
private struct ToastCard: View {
    let toast: Toast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.type.icon)
                .font(.title3)
                .foregroundColor(.white)
            
            Text(toast.message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .lineLimit(3)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: maxToastWidth)
        .background(toast.type.color)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, horizontalPadding)
    }
    
    // iPad: centered with max width, iPhone: full width with padding
    private var maxToastWidth: CGFloat? {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 480
        }
        #endif
        return nil
    }
    
    private var horizontalPadding: CGFloat {
        #if os(iOS)
        if UIDevice.current.userInterfaceIdiom == .pad {
            return 0 // Centered, no horizontal padding needed
        }
        #endif
        return 20
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        
        VStack {
            Spacer()
            
            Button("Show Success") {
                ToastCenter.shared.show("Item added to pantry!", type: .success)
            }
            
            Button("Show Error") {
                ToastCenter.shared.show("Failed to add item to inventory", type: .error)
            }
            
            Button("Show Info") {
                ToastCenter.shared.show("Syncing with server...", type: .info)
            }
            
            Button("Show Warning") {
                ToastCenter.shared.show("Low storage space", type: .warning)
            }
            
            Button("Show Multiple") {
                ToastCenter.shared.show("First message", type: .success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    ToastCenter.shared.show("Second message", type: .info)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    ToastCenter.shared.show("Third message", type: .warning)
                }
            }
        }
        .padding()
        
        ToastHostView()
    }
}
