import SwiftUI

struct AddCustomItemView: View {
    @Binding var viewModel: InventoryViewModel
    @Binding var isPresented: Bool
    @Environment(AuthViewModel.self) private var authViewModel
    var prefilledUPC: String?
    var onItemAdded: ((String) -> Void)?
    
    @State private var name = ""
    @State private var brand = ""
    @State private var upc = ""
    @State private var quantity = 1
    @State private var showingDatePicker = false
    @State private var expirationDate = Date()
    @State private var isLoading = false
    @State private var showingScanner = false
    @State private var selectedLocationId: String = ""
    
    private var canSubmit: Bool {
        !name.isEmpty && !selectedLocationId.isEmpty && !isLoading
    }
    
    private var validationMessage: String? {
        if name.isEmpty {
            return nil // Don't show validation until user tries to submit
        }
        if selectedLocationId.isEmpty {
            return "Please select a storage location"
        }
        return nil
    }
    
    @ViewBuilder
    private var emptyLocationsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("No storage locations available")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Text("Go to Settings → Storage Locations to create locations")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var locationValidationView: some View {
        if let message = validationMessage {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Product Info") {
                    TextField("Product Name *", text: $name)
                        .accessibilityIdentifier("addItem.nameField")
                    TextField("Brand", text: $brand)
                        .accessibilityIdentifier("addItem.brandField")
                    
                    HStack {
                        TextField("UPC (optional)", text: $upc)
                        
                        Button(action: { showingScanner = true }) {
                            Image(systemName: "barcode.viewfinder")
                                .foregroundColor(.ppPurple)
                        }
                    }
                }
                
                Section {
                    if viewModel.locations.isEmpty {
                        emptyLocationsView
                    } else {
                        Picker("Storage Location", selection: $selectedLocationId) {
                            ForEach(viewModel.locations) { location in
                                Text(location.fullPath).tag(location.id)
                            }
                        }
                        
                        locationValidationView
                    }
                } header: {
                    Text("Location")
                } footer: {
                    Text("Location is required to add items to your inventory")
                        .font(.caption)
                }
                
                Section("Inventory") {
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                    
                    Toggle("Add expiration date", isOn: $showingDatePicker)
                    
                    if showingDatePicker {
                        DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Add Custom Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveItem() }
                    }
                    .disabled(!canSubmit)
                    .accessibilityIdentifier("addItem.saveButton")
                }
            }
            .onAppear {
                if let upc = prefilledUPC {
                    self.upc = upc
                }
                selectDefaultLocation()
            }
            .onChange(of: viewModel.locations) { _, _ in
                selectDefaultLocation()
            }
            .onChange(of: selectedLocationId) { _, newLocationId in
                if !newLocationId.isEmpty {
                    LastUsedLocationStore.shared.setLastLocation(newLocationId, for: authViewModel.currentHousehold?.id)
                }
            }
            .sheet(isPresented: $showingScanner) {
                UPCScannerSheet(scannedUPC: $upc, isPresented: $showingScanner)
            }
        }
    }
    
    private func selectDefaultLocation() {
        if selectedLocationId.isEmpty {
            let householdId = authViewModel.currentHousehold?.id
            let defaultLocationId = viewModel.locations.first(where: { $0.name == "Pantry" })?.id ?? viewModel.locations.first?.id ?? "pantry"
            
            selectedLocationId = LastUsedLocationStore.shared.getSafeDefaultLocation(
                for: householdId,
                availableLocations: viewModel.locations,
                defaultLocationId: defaultLocationId
            )
        }
    }
    
    private func saveItem() async {
        isLoading = true
        
        guard !selectedLocationId.isEmpty else {
            viewModel.errorMessage = "Please select a location"
            isLoading = false
            return
        }
        
        do {
            let product = try await APIService.shared.createProduct(
                upc: upc.isEmpty ? nil : upc,
                name: name,
                brand: brand.isEmpty ? nil : brand,
                description: nil,
                category: nil
            )
            
            let success = await viewModel.addCustomItem(
                product: product,
                quantity: quantity,
                expirationDate: showingDatePicker ? expirationDate : nil,
                locationId: selectedLocationId
            )
            
            if success {
                let productName = name
                isPresented = false
                onItemAdded?(productName)
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
            HapticService.shared.error()
        }
        
        isLoading = false
    }
}
