import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GroceryViewModel()
    @State private var showingAddSheet = false
    @State private var showingSettings = false
    @State private var showingPaywall = false
    @State private var newItemName = ""
    @FocusState private var isInputFocused: Bool
    
    private var isPremium: Bool {
        authViewModel.currentHousehold?.isPremiumActive ?? false
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    itemsList
                }
            }
            .accessibilityIdentifier("grocery.list")
            .navigationTitle("Grocery List")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "person.circle")
                    }
                    .accessibilityIdentifier("settings.button")
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        checkAndShowPaywallIfAtLimit()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                    }
                    .accessibilityIdentifier("grocery.addButton")
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                addItemSheet
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environment(authViewModel)
                    .environmentObject(NotificationService.shared)
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
                    .environment(authViewModel)
            }
            .task {
                viewModel.setModelContext(modelContext)
                if viewModel.items.isEmpty {
                    await viewModel.fetchItems()
                }
            }
            .refreshable {
                await viewModel.fetchItems()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("householdDataDeleted"))) { _ in
                print("🗑️ [GroceryListView] Household data deleted notification received")
                print("🗑️ [GroceryListView] Current items count before reload: \(viewModel.items.count)")
                Task {
                    print("🗑️ [GroceryListView] Starting fetchItems()...")
                    await viewModel.fetchItems()
                    print("🗑️ [GroceryListView] After fetchItems(), items count: \(viewModel.items.count)")
                }
            }
        }
    }
    
    private var itemsList: some View {
        List {
            ForEach(viewModel.items) { item in
                HStack {
                    Image(systemName: "cart")
                        .foregroundStyle(.secondary)
                    
                    Text(item.displayName)
                        .font(.body)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.removeItem(item)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            
            Text("No Items Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            if isPremium {
                Text("PantryPal will auto-add items to your Grocery List when you run out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Add items manually, or upgrade to Premium to auto-add them when you run out.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button {
                checkAndShowPaywallIfAtLimit()
            } label: {
                Label("Add Item", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .padding()
    }
    
    private var addItemSheet: some View {
        NavigationStack {
            VStack(spacing: 20) {
                AppTextField(
                    placeholder: "Item name",
                    text: $newItemName,
                    autocapitalization: .words,
                    autocorrectionDisabled: true
                )
                .focused($isInputFocused)
                .submitLabel(.done)
                .onSubmit {
                    addItem()
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showingAddSheet = false
                        newItemName = ""
                        viewModel.errorMessage = nil
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addItem()
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                isInputFocused = true
            }
        }
    }
    
    private func addItem() {
        Task {
            let success = await viewModel.addItem(name: newItemName)
            if success {
                showingAddSheet = false
                newItemName = ""
                viewModel.errorMessage = nil
            }
        }
    }
    
    @MainActor
    private func checkAndShowPaywallIfAtLimit() {
        // Only check for non-Premium users
        guard !isPremium else {
            print("💎 [GroceryList] User is Premium, skipping limit check")
            showingAddSheet = true
            return
        }
        
        let itemCount = viewModel.items.count
        print("📊 [GroceryList] Current grocery item count: \(itemCount)")
        
        if itemCount >= 25 {
            print("🚨 [GroceryList] User has reached the 25 grocery item limit!")
            print("   - Will show paywall")
            
            // Show toast message
            ToastCenter.shared.show("You've reached your 25 grocery item limit. Upgrade to add unlimited items!", type: .info)
            
            // Small delay then show paywall
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                print("💰 [GroceryList] Showing paywall")
                self.showingPaywall = true
            }
        } else {
            print("✅ [GroceryList] Under limit (\(itemCount)/25), showing add sheet")
            showingAddSheet = true
        }
    }
}

#Preview {
    GroceryListView()
        .environment(AuthViewModel())
}
