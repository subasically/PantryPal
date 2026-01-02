import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var size = 0.8
    @State private var opacity = 0.5
    
    var body: some View {
        if isActive {
            ContentView()
        } else {
            VStack {
                VStack {
                    Image(systemName: "refrigerator.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(LinearGradient.ppPrimaryGradient)
                    
                    Text("PantryPal")
                        .font(.system(size: 40))
                        .fontWeight(.bold)
                        .foregroundColor(.ppPurple)
                }
                .scaleEffect(size)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.easeIn(duration: 1.2)) {
                        self.size = 0.9
                        self.opacity = 1.00
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(UIColor.systemBackground))
            .onAppear {
                // Skip splash delay during UI testing
                let delay = CommandLine.arguments.contains("--uitesting") ? 0.1 : 2.0
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation {
                        self.isActive = true
                    }
                }
            }
        }
    }
}

#Preview {
    SplashView()
        .environment(AuthViewModel())
}
