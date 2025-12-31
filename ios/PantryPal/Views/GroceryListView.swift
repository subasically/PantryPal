import SwiftUI
import SwiftData

struct GroceryListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = GroceryViewModel()
    @State private var showingAddSheet = false
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddSheet = true
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
            .task {
                viewModel.setModelContext(modelContext)
                if viewModel.items.isEmpty {
                    await viewModel.fetchItems()
                }
            }
            .refreshable {
                await viewModel.fetchItems()
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
                VStack(spacing: 8) {
                    Text("PantryPal will auto-add items to your Grocery List when you run out.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Text("Add items manually, or upgrade to Premium to auto-add them when you run out.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button {
                        // Trigger paywall
                        NotificationCenter.default.post(name: .showPaywall, object: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                            Text("Auto-add is a Premium feature")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.ppPurple)
                        .clipShape(Capsule())
                    }
                }
            }
            
            Button {
                showingAddSheet = true
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
}

#Preview {
    GroceryListView()
        .environment(AuthViewModel())
}
