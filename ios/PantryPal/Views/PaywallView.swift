import SwiftUI
import StoreKit

enum PaywallReason {
    case itemLimit
    case householdSharing
}

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthViewModel.self) private var authViewModel
    @EnvironmentObject private var confettiCenter: ConfettiCenter
    @StateObject private var storeKit = StoreKitService.shared
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showDebugAlert = false
    @State private var debugErrorMessage: String?
    @State private var showThankYou = false
    
    var limit: Int = 25
    var reason: PaywallReason = .itemLimit
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Image
                    Image(systemName: "crown.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.ppPurple, .ppBlue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .padding(.top, 40)
                    
                    VStack(spacing: 12) {
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
                    VStack(alignment: .leading, spacing: 24) {
                        FeatureRow(icon: "infinity", title: "Unlimited Items", description: "Store as many items as you need")
                        FeatureRow(icon: "person.2.fill", title: "Household Sharing", description: "Sync with your family in real-time")
                        FeatureRow(icon: "icloud.fill", title: "Cloud Sync Across Devices", description: "Reliable backup for all your devices")
                        FeatureRow(icon: "cart.fill.badge.plus", title: "Auto-add to Grocery", description: "Never forget what you need to buy")
                        FeatureRow(icon: "bell.badge.fill", title: "Smart Notifications", description: "Get alerts before items expire")
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
                        Task {
                            await purchaseProduct(storeKit.annualProduct)
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            }
                            
                            VStack(spacing: 4) {
                                if let annual = storeKit.annualProduct {
                                    Text("Subscribe for \(annual.displayPrice)/year")
                                        .font(.headline)
                                    Text("Save 17% • Best Value")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .opacity(0.9)
                                } else {
                                    Text("Loading...")
                                        .font(.headline)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.ppPurple)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .opacity(isLoading || storeKit.annualProduct == nil ? 0.6 : 1.0)
                    }
                    .disabled(isLoading || storeKit.annualProduct == nil)
                    
                    // Monthly (Secondary)
                    Button(action: {
                        Task {
                            await purchaseProduct(storeKit.monthlyProduct)
                        }
                    }) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                            }
                            
                            VStack(spacing: 4) {
                                if let monthly = storeKit.monthlyProduct {
                                    Text("Subscribe for \(monthly.displayPrice)/month")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                } else {
                                    Text("Loading...")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.15))
                        .cornerRadius(12)
                        .opacity(isLoading || storeKit.monthlyProduct == nil ? 0.6 : 1.0)
                    }
                    .disabled(isLoading || storeKit.monthlyProduct == nil)
                    
                    Text("No ads. No tracking. Cancel anytime.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                    
                    Button("Restore Purchases") {
                        Task {
                            await restorePurchases()
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
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let error = errorMessage {
                    Text(error)
                }
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
            .task {
                // Load products when view appears
                do {
                    try await storeKit.loadProducts()
                } catch {
                    errorMessage = "Failed to load products: \(error.localizedDescription)"
                }
            }
            .fullScreenCover(isPresented: $showThankYou) {
                ThankYouView()
                    .environmentObject(confettiCenter)
                    .onDisappear {
                        // Dismiss the paywall when thank you view is dismissed
                        dismiss()
                    }
            }
        }
    }
    
    // MARK: - Purchase Methods
    
    private func purchaseProduct(_ product: StoreKit.Product?) async {
        guard let product = product else {
            errorMessage = "Product not available"
            return
        }
        
        errorMessage = nil // Clear any previous errors
        isLoading = true
        
        do {
            let (transaction, updatedHousehold) = try await storeKit.purchase(product)
            
            if transaction != nil {
                // Purchase successful - update local household immediately with server response
                if let household = updatedHousehold {
                    print("📦 [PaywallView] Household from response:")
                    print("  - ID: \(household.id)")
                    print("  - isPremium: \(household.isPremium ?? false)")
                    print("  - premiumExpiresAt: \(household.premiumExpiresAt ?? "nil")")
                    print("  - isPremiumActive: \(household.isPremiumActive)")
                    
                    authViewModel.currentHousehold = household
                    print("✅ [PaywallView] Updated authViewModel.currentHousehold")
                    print("🔍 [PaywallView] Verifying update - authViewModel.currentHousehold.isPremiumActive: \(authViewModel.currentHousehold?.isPremiumActive ?? false)")
                    
                    // Update NotificationService so it can schedule notifications
                    NotificationService.shared.currentHousehold = household
                } else {
                    // Fallback to refresh if household wasn't in response
                    print("⚠️ [PaywallView] No household in response, refreshing from server...")
                    await authViewModel.refreshCurrentUser()
                }
                
                // Keep loading state active until Thank You view appears
                // Show Thank You view
                showThankYou = true
                
                // Stop loading after a brief delay (Thank You view takes over)
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                isLoading = false
            } else {
                // Transaction is nil - user cancelled or interrupted
                print("ℹ️ [PaywallView] Purchase cancelled or interrupted, no error shown")
                isLoading = false
            }
        } catch {
            print("❌ [PaywallView] Purchase error: \(error)")
            isLoading = false
            if let storeError = error as? StoreError {
                errorMessage = storeError.errorDescription
            } else {
                errorMessage = "Purchase failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await storeKit.restorePurchases()
            
            // Refresh user data to get updated premium status
            await authViewModel.refreshCurrentUser()
            
            // Check if user is now premium
            if authViewModel.currentHousehold?.isPremiumActive == true {
                ToastCenter.shared.show(
                    "Purchases restored successfully!",
                    type: .success
                )
                dismiss()
            } else {
                ToastCenter.shared.show(
                    "No active subscriptions found",
                    type: .info
                )
            }
        } catch {
            errorMessage = "Failed to restore purchases: \(error.localizedDescription)"
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
        .environmentObject(ConfettiCenter())
}
