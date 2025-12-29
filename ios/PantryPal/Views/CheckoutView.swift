import SwiftUI

struct CheckoutView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = CheckoutViewModel()
    @State private var scannedCode: String?
    @State private var showHistory = false
    @State private var isScanning = true
    
    // Toast state
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastView.ToastType = .success
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Scanner
                BarcodeScannerView(scannedCode: $scannedCode, isScanning: $isScanning, isPresented: .constant(true)) { code in
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
            .toast(isShowing: $showToast, message: toastMessage, type: toastType)
            .onAppear {
                viewModel.setContext(modelContext)
            }
            .onDisappear {
                viewModel.lastCheckout = nil
                scannedCode = nil
                viewModel.errorMessage = nil
            }
            .onChange(of: viewModel.lastCheckout) { _, newValue in
                if let response = newValue, response.success == true {
                    toastMessage = "Checked out \(response.product?.name ?? "item")"
                    toastType = .success
                    showToast = true
                }
            }
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
                                
                                Text("by \(item.userName)")
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
    
    private func loadHistory() async {
        do {
            let response = try await APIService.shared.getCheckoutHistory()
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
