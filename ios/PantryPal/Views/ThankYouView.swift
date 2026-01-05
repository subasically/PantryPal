import SwiftUI

struct ThankYouView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var confettiCenter: ConfettiCenter
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Profile Image
                    if let image = UIImage(named: "developer-photo") {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [.ppPurple, .ppBlue],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 4
                                    )
                            )
                            .shadow(radius: 10)
                            .padding(.top, 40)
                    }
                    
                    // Title
                    Text("Thank You! 🎉")
                        .font(.system(size: 36, weight: .bold))
                        .multilineTextAlignment(.center)
                    
                    // Personal Message
                    VStack(spacing: 24) {
                        Text("Thank you for supporting PantryPal! As a solo developer, father, and husband, your subscription means everything to me. It helps me continue building this app for families like yours. You're not just unlocking premium features—you're keeping this dream alive.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Text("With gratitude 🙏")
                            .font(.body)
                            .italic()
                            .padding(.top, 8)
                        
                        Text("Alen")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.ppPurple, .ppBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    .padding(.horizontal, 24)
                    
                    // Premium Badge
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.ppPurple, .ppBlue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("You're now a Premium member")
                            .font(.headline)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    
                    // Continue Button
                    Button {
                        dismiss()
                    } label: {
                        Text("Continue to PantryPal")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(
                                LinearGradient(
                                    colors: [.ppPurple, .ppBlue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .overlay {
                if confettiCenter.isActive {
                    ConfettiOverlay()
                }
            }
            .onAppear {
                // Trigger confetti when view appears
                confettiCenter.celebrate(duration: 4.0)
                HapticService.shared.success()
            }
        }
    }
}

#Preview {
    ThankYouView()
        .environmentObject(ConfettiCenter())
}
