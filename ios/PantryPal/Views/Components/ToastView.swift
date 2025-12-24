import SwiftUI

struct ToastView: View {
    let message: String
    let type: ToastType
    
    enum ToastType {
        case success, error, info
        
        var color: Color {
            switch self {
            case .success: return .ppGreen
            case .error: return .ppDanger
            case .info: return .ppPurple
            }
        }
        
        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.title3)
                .foregroundColor(.white)
            
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(type.color)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 20)
    }
}

struct ToastModifier: ViewModifier {
    @Binding var isShowing: Bool
    let message: String
    let type: ToastView.ToastType
    let duration: Double
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            VStack {
                if isShowing {
                    ToastView(message: message, type: type)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation(.easeOut(duration: 0.3)) {
                                    isShowing = false
                                }
                            }
                        }
                }
                Spacer()
            }
            .padding(.top, 50)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isShowing)
    }
}

extension View {
    func toast(isShowing: Binding<Bool>, message: String, type: ToastView.ToastType = .success, duration: Double = 2.0) -> some View {
        modifier(ToastModifier(isShowing: isShowing, message: message, type: type, duration: duration))
    }
}

#Preview {
    VStack {
        ToastView(message: "Item added to pantry!", type: .success)
        ToastView(message: "Failed to add item", type: .error)
        ToastView(message: "Scanning barcode...", type: .info)
    }
    .padding()
}
