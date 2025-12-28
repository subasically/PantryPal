import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Image
                    Image(systemName: "crown.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.ppPurple, .ppBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 40)
                    
                    VStack(spacing: 8) {
                        Text("Unlock Unlimited Pantry")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("You've reached the 50-item limit.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Features List
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(icon: "infinity", title: "Unlimited Items", description: "Store as many items as you need")
                        FeatureRow(icon: "person.2.fill", title: "Household Sharing", description: "Sync with your family in real-time")
                        FeatureRow(icon: "icloud.fill", title: "Priority Sync", description: "Faster, more reliable cloud backup")
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // Pricing
                    VStack(spacing: 16) {
                        Button(action: {
                            // TODO: Implement In-App Purchase
                        }) {
                            VStack(spacing: 4) {
                                Text("Subscribe for $4.99/month")
                                    .font(.headline)
                                Text("Cancel anytime")
                                    .font(.caption)
                                    .opacity(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.ppPrimary)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        Button(action: {
                            // TODO: Implement In-App Purchase
                        }) {
                            VStack(spacing: 4) {
                                Text("Subscribe for $49.99/year")
                                    .font(.headline)
                                Text("Save 17%")
                                    .font(.caption)
                                    .foregroundColor(.ppGreen)
                                    .fontWeight(.bold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.ppSecondary)
                            .foregroundColor(.ppPrimary)
                            .cornerRadius(12)
                        }
                        
                        Button("Restore Purchases") {
                            // TODO: Implement Restore
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.ppPurple)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    PaywallView()
}
