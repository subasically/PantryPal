import SwiftUI

enum PaywallReason {
    case itemLimit
    case householdSharing
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel
    @EnvironmentObject private var confettiCenter: ConfettiCenter
    @State private var isLoading = false
    @State private var showDebugAlert = false
    @State private var debugErrorMessage: String?
    
    var limit: Int = 25
    var reason: PaywallReason = .itemLimit
    
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
                        if reason == .householdSharing {
                            Text("Unlock Household Sharing")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Invite family members to manage your pantry together.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        } else {
                            Text("Unlock Unlimited Items")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("You've reached the \(limit)-item limit.")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Features List
                    VStack(alignment: .leading, spacing: 20) {
                        FeatureRow(icon: "infinity", title: "Unlimited Items", description: "Store as many items as you need")
                        FeatureRow(icon: "person.2.fill", title: "Household Sharing", description: "Sync with your family in real-time")
                        FeatureRow(icon: "icloud.fill", title: "Cloud Sync Across Devices", description: "Reliable backup for all your devices")
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(16)
                    .padding(.horizontal)
                }
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 16) {
                    // Yearly (Primary)
                    Button(action: {
                        isLoading = true
                        // TODO: Implement In-App Purchase
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            isLoading = false
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text("Subscribe for $49.99/year")
                                .font(.headline)
                            Text("Save 17% • Best Value")
                                .font(.caption)
                                .fontWeight(.bold)
                                .opacity(0.9)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.ppPurple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isLoading)
                    
                    // Monthly (Secondary)
                    Button(action: {
                        isLoading = true
                        // TODO: Implement In-App Purchase
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            isLoading = false
                        }
                    }) {
                        VStack(spacing: 4) {
                            Text("Subscribe for $4.99/month")
                                .font(.headline)
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                    }
                    .disabled(isLoading)
                    
                    Text("No ads. No tracking. Cancel anytime.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    Button("Restore Purchases") {
                        isLoading = true
                        // TODO: Implement Restore
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            isLoading = false
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .disabled(isLoading)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
                
                #if DEBUG
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await simulatePremiumUpgrade()
                        }
                    } label: {
                        Label("Simulate Premium", systemImage: "ladybug.fill")
                            .foregroundColor(.orange)
                    }
                    .disabled(isLoading)
                }
                
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        confettiCenter.celebrate()
                    } label: {
                        Label("Test Confetti", systemImage: "party.popper.fill")
                            .foregroundColor(.purple)
                    }
                }
                #endif
            }
            .alert("Debug Error", isPresented: .constant(debugErrorMessage != nil)) {
                Button("OK") {
                    debugErrorMessage = nil
                }
            } message: {
                if let error = debugErrorMessage {
                    Text(error)
                }
            }
            .overlay {
                if confettiCenter.isActive {
                    ConfettiOverlay()
                }
            }
        }
    }
    
    #if DEBUG
    private func simulatePremiumUpgrade() async {
        guard let householdId = authViewModel.currentUser?.householdId else {
            debugErrorMessage = "No household ID found"
            return
        }
        
        // Admin key - in real app, would be in secure config or prompt user
        // For dev/test, hardcode or read from environment
        let adminKey = "dev-admin-key-change-me"
        
        isLoading = true
        
        do {
            let success = try await APIService.shared.simulatePremiumUpgrade(
                householdId: householdId,
                adminKey: adminKey
            )
            
            if success {
                // Refresh user data to get updated household premium status
                await authViewModel.refreshCurrentUser()
                
                // Trigger confetti celebration
                confettiCenter.celebrate()
                
                // Dismiss paywall after a slight delay to let confetti start
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                dismiss()
            } else {
                debugErrorMessage = "Premium upgrade returned false"
            }
        } catch {
            debugErrorMessage = "Failed: \(error.userFriendlyMessage)"
        }
        
        isLoading = false
    }
    #endif
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
        .environment(AuthViewModel())
}
