import SwiftUI

struct CheckoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var viewModel = CheckoutViewModel()
    @State private var scannedCode: String?
    @State private var showHistory = false
    @State private var isScanning = true
    
    // Grocery add confirmation (for Free users)
    @State private var showGroceryPrompt = false
    @State private var pendingGroceryItem: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Scanner
                BarcodeScannerView(scannedCode: $scannedCode, isPresented: .constant(true), isScanning: $isScanning) { code in
                    isScanning = false
                    Task {
                        await viewModel.processCheckout(upc: code)
                    }
                }
                
                // Overlay UI
                VStack {
                    Spacer()
                    
                    // Result card
                    if let checkout = viewModel.lastCheckout {
                        checkoutResultCard(checkout)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    
                    if let error = viewModel.errorMessage {
                        errorCard(error)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.4), value: viewModel.lastCheckout != nil)
                .animation(.spring(response: 0.4), value: viewModel.errorMessage != nil)
                
                // Processing indicator
                if viewModel.isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .accessibilityIdentifier("checkout.tabButton")
            .navigationTitle("Checkout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showHistory = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showHistory) {
                CheckoutHistoryView()
            }
            .onAppear {
                viewModel.setContext(modelContext)
            }
            .onDisappear {
                viewModel.lastCheckout = nil
                scannedCode = nil
                viewModel.errorMessage = nil
            }
            .onChange(of: viewModel.lastCheckout) { _, newValue in
                handleCheckoutResponse(newValue)
            }
            .alert("Add to Grocery List?", isPresented: $showGroceryPrompt) {
                Button("Not now", role: .cancel) {
                    pendingGroceryItem = nil
                }
                Button("Add", role: .none) {
                    if let itemName = pendingGroceryItem {
                        Task {
                            await addToGroceryList(itemName)
                        }
                    }
                    pendingGroceryItem = nil
                }
            } message: {
                if let itemName = pendingGroceryItem {
                    Text("You're out of \(itemName). Add it to your grocery list?")
                }
            }
        }
    }
    
    private func handleCheckoutResponse(_ response: CheckoutScanResponse?) {
        guard let response = response, response.success == true else { return }
        
        let isPremium = authViewModel.currentHousehold?.isPremiumActive ?? false
        
        print("🛒 [CheckoutGrocery] handleCheckoutResponse called")
        print("🛒 [CheckoutGrocery] - itemDeleted: \(response.itemDeleted == true)")
        print("🛒 [CheckoutGrocery] - productName: \(response.productName ?? "nil")")
        print("🛒 [CheckoutGrocery] - isPremium: \(isPremium)")
        print("🛒 [CheckoutGrocery] - addedToGrocery (server): \(response.addedToGrocery == true)")
        
        // Check if item was deleted (quantity went to 0)
        if response.itemDeleted == true, let productName = response.productName {
            print("🛒 [CheckoutGrocery] Item hit zero during checkout")
            
            // Only Premium users get the confirmation prompt
            guard isPremium else {
                print("🛒 [CheckoutGrocery] User is not Premium, skipping grocery prompt")
                ToastCenter.shared.show("Checked out last \(productName)", type: .success)
                return
            }
            
            print("🛒 [CheckoutGrocery] Showing confirmation prompt")
            pendingGroceryItem = productName
            showGroceryPrompt = true
        } else {
            // Normal checkout (item still in stock)
            print("🛒 [CheckoutGrocery] Regular checkout, item not deleted")
            ToastCenter.shared.show("Checked out \(response.product?.name ?? "item")", type: .success)
        }
    }
    
    private func addToGroceryList(_ itemName: String) async {
        do {
            _ = try await APIService.shared.addGroceryItem(name: itemName)
            ToastCenter.shared.show("✓ Added to grocery list", type: .success)
        } catch {
            ToastCenter.shared.show("Failed to add to grocery list", type: .error)
        }
    }
    
    private func checkoutResultCard(_ checkout: CheckoutScanResponse) -> some View {
        VStack(spacing: 12) {
            if checkout.success == true {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.ppGreen)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(checkout.product?.name ?? "Item")
                            .font(.headline)
                        
                        if let brand = checkout.product?.brand {
                            Text(brand)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Text("\(checkout.previousQuantity ?? 0) → \(checkout.newQuantity ?? 0) remaining")
                            .font(.caption)
                            .foregroundColor(.ppOrange)
                    }
                    
                    Spacer()
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title)
                        .foregroundColor(.ppOrange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(checkout.error ?? "Unknown error")
                            .font(.headline)
                        
                        if checkout.found == true && checkout.inStock == false {
                            Text("Product found but not in stock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if checkout.found == false {
                            Text("UPC: \(checkout.upc ?? "Unknown")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
            }
            
            Button("Scan Another") {
                withAnimation {
                    viewModel.lastCheckout = nil
                    scannedCode = nil
                    isScanning = true
                }
            }
            .buttonStyle(.ppSecondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .padding()
    }
    
    private func errorCard(_ error: String) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundColor(.ppDanger)
                
                Text(error)
                    .font(.headline)
                
                Spacer()
            }
            
            Button("Try Again") {
                withAnimation {
                    viewModel.errorMessage = nil
                    scannedCode = nil
                    isScanning = true
                }
            }
            .buttonStyle(.ppSecondary)
        }
        .padding()
        .background(.regularMaterial)
        .cornerRadius(16)
        .padding()
    }
}

struct CheckoutHistoryView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @State private var history: [CheckoutHistoryItem] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if history.isEmpty {
                    ContentUnavailableView(
                        "No Checkout History",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Items you check out will appear here")
                    )
                } else {
                    List(history) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.productName)
                                    .font(.headline)
                                
                                if let brand = item.productBrand {
                                    Text(brand)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                // Smart actor display
                                Text(getActorDisplay(for: item))
                                    .font(.caption)
                                    .foregroundColor(.ppPurple)
                            }
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("-\(item.quantity)")
                                    .font(.headline)
                                    .foregroundColor(.ppOrange)
                                
                                Text(formatDate(item.checkedOutAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Checkout History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadHistory()
            }
        }
    }
    
    private func getActorDisplay(for item: CheckoutHistoryItem) -> String {
        // Check if this checkout was by current user
        if item.userId == authViewModel.currentUser?.id {
            return "by You"
        }
        // Otherwise show the name (with fallback handled in model)
        return "by \(item.userName)"
    }
    
    private func loadHistory() async {
        isLoading = true
        do {
            let response = try await APIService.shared.getCheckoutHistory()
            
            #if DEBUG
            print("📦 [CheckoutHistory] Fetched \(response.history.count) items")
            if let first = response.history.first {
                print("📦 [CheckoutHistory] First item - userId: \(first.userId), userName: '\(first.userName)'")
            }
            #endif
            
            // CRITICAL: Replace array, don't append
            history = response.history
        } catch {
            print("Failed to load history: \(error)")
        }
        isLoading = false
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        
        return dateString
    }
}

#Preview {
    CheckoutView()
}
