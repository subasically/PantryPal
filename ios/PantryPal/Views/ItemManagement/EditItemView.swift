import SwiftUI

struct EditItemView: View {
    let item: InventoryItem
    @Binding var viewModel: InventoryViewModel
    @Binding var editingItem: InventoryItem?
    
    @State private var quantity: Int
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    @State private var notes: String
    @State private var selectedLocationId: String
    @State private var isLoading = false
    @State private var validationError: String?
    
    private var canSave: Bool {
        // Location must be valid - cannot be empty
        guard !selectedLocationId.isEmpty else {
            return false
        }
        // Must be a valid location from the list
        return viewModel.locations.contains(where: { $0.id == selectedLocationId })
    }
    
    init(item: InventoryItem, viewModel: Binding<InventoryViewModel>, editingItem: Binding<InventoryItem?>) {
        self.item = item
        self._viewModel = viewModel
        self._editingItem = editingItem
        self._quantity = State(initialValue: item.quantity)
        self._hasExpiration = State(initialValue: item.expirationDate != nil)
        self._notes = State(initialValue: item.notes ?? "")
        
        // Initialize location - use item's location or fallback to first available
        let initialLocation = item.locationId ?? viewModel.wrappedValue.locations.first?.id ?? ""
        self._selectedLocationId = State(initialValue: initialLocation)
        
        // Parse expiration date
        if let expDateStr = item.expirationDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            self._expirationDate = State(initialValue: formatter.date(from: expDateStr) ?? Date())
        } else {
            self._expirationDate = State(initialValue: Date())
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Product") {
                    HStack {
                        Text("Name")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(item.displayName)
                    }
                    
                    if let brand = item.productBrand {
                        HStack {
                            Text("Brand")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(brand)
                        }
                    }
                    
                    if let upc = item.productUpc {
                        HStack {
                            Text("UPC")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(upc)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section("Inventory") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...999)
                }
                
                Section("Location") {
                    if viewModel.locations.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.ppOrange)
                            Text("No locations available")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Storage Location", selection: $selectedLocationId) {
                            ForEach(viewModel.locations) { location in
                                Text(location.fullPath).tag(location.id)
                            }
                        }
                    }
                    
                    Text("Location is required for all inventory items")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Expiration") {
                    Toggle("Has expiration date", isOn: $hasExpiration)
                    
                    if hasExpiration {
                        DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)
                        
                        // Show expiration status
                        if expirationDate < Date() {
                            Label("This item has expired", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.ppDanger)
                        } else if expirationDate < Date().addingTimeInterval(7 * 24 * 60 * 60) {
                            Label("Expiring soon", systemImage: "clock.fill")
                                .foregroundColor(.ppOrange)
                        } else {
                            Label("Fresh", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.ppGreen)
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Add notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.deleteItem(id: item.id)
                            editingItem = nil
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Delete Item", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        editingItem = nil
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(isLoading || !canSave)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                }
            }
        }
    }
    
    private func saveChanges() {
        // Validate location before saving
        guard !selectedLocationId.isEmpty else {
            validationError = "Location required"
            HapticService.shared.error()
            return
        }
        
        guard viewModel.locations.contains(where: { $0.id == selectedLocationId }) else {
            validationError = "Invalid location"
            HapticService.shared.error()
            return
        }
        
        isLoading = true
        validationError = nil
        
        Task {
            await viewModel.updateItem(
                id: item.id,
                quantity: quantity,
                expirationDate: hasExpiration ? expirationDate : nil,
                notes: notes.isEmpty ? nil : notes,
                locationId: selectedLocationId
            )
            editingItem = nil
            isLoading = false
        }
    }
}

