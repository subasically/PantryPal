import SwiftUI

struct ScannerSheet: View {
    @Binding var viewModel: InventoryViewModel
    @Binding var isPresented: Bool
    @Environment(AuthViewModel.self) private var authViewModel
    var onItemAdded: ((String) -> Void)?
    
    @State private var scannedCode: String?
    @State private var showingDatePicker = false
    @State private var expirationDate = Date()
    @State private var quantity = 1
    @State private var showingCustomProductForm = false
    @State private var pendingUPC: String?
    @State private var lookupResult: UPCLookupResponse?
    @State private var isLookingUp = false
    @State private var selectedLocationId: String = ""
    
    // Custom product fields for inline entry
    @State private var customName = ""
    @State private var customBrand = ""
    @State private var isAddingCustom = false
    
    // Edit mode for found products
    @State private var isEditingFoundProduct = false
    @State private var editedName = ""
    @State private var editedBrand = ""
    
    @State private var existingItem: InventoryItem?
    @State private var isScanning = true
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Camera View (Always visible)
            BarcodeScannerView(scannedCode: $scannedCode, isPresented: .constant(true), isScanning: $isScanning) { code in
                scannedCode = code
                HapticService.shared.mediumImpact()
                lookupProduct(upc: code)
            }
            .edgesIgnoringSafeArea(.all)
            
            // Overlay Sheet
            if scannedCode != nil {
                VStack(spacing: 0) {
                    // Handle bar
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 40, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 10)
                    
                    scannedResultView
                        .padding(.bottom, 20)
                }
                .background(Color(uiColor: .systemBackground))
                .cornerRadius(20)
                .shadow(radius: 10)
                .transition(.move(edge: .bottom))
                .padding(.bottom, 0)
            }
            
            // Close button (top left)
            VStack {
                HStack {
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                    .padding()
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
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
    
    private var scannedResultView: some View {
        VStack(spacing: 16) {
            // Product Details Header
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.ppPurple.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.ppPurple)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    if isLookingUp {
                        Text("Looking up...")
                            .font(.headline)
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let result = lookupResult {
                        if result.found, let product = result.product {
                            Text(editedName.isEmpty ? product.name : editedName)
                                .font(.headline)
                                .lineLimit(2)
                            
                            let displayBrand = editedBrand.isEmpty ? product.brand : editedBrand
                            if let brand = displayBrand, !brand.isEmpty {
                                Text(brand)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("New Item")
                                .font(.headline)
                            Text("Enter details below")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Edit button (only if found)
                if let result = lookupResult, result.found {
                    Button {
                        isEditingFoundProduct.toggle()
                        if isEditingFoundProduct {
                            editedName = result.product?.name ?? ""
                            editedBrand = result.product?.brand ?? ""
                        }
                    } label: {
                        Image(systemName: isEditingFoundProduct ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.title2)
                            .foregroundColor(.ppPurple)
                    }
                }
            }
            .padding(.horizontal)
            
            // Edit Fields (if editing or new)
            if isEditingFoundProduct || isProductNotFound {
                VStack(spacing: 12) {
                    if isProductNotFound {
                        TextField("Product Name", text: $customName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Brand (optional)", text: $customBrand)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField("Product Name", text: $editedName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Brand (optional)", text: $editedBrand)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                .padding(.horizontal)
            }
            
            // Options Container
            VStack(spacing: 0) {
                // Row 1: Location + Quantity
                HStack {
                    // Location Picker
                    if !viewModel.locations.isEmpty {
                        HStack(spacing: 4) {
                            Text("Location")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Picker("Location", selection: $selectedLocationId) {
                                ForEach(viewModel.locations) { location in
                                    Text(location.name).tag(location.id)
                                }
                            }
                            .labelsHidden()
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .fixedSize()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Spacer()
                    
                    // Quantity Stepper
                    HStack(spacing: 8) {
                        Text("Qty")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Stepper(value: $quantity, in: 1...99) {
                            EmptyView()
                        }
                        .labelsHidden()
                        
                        Text("\(quantity)")
                            .font(.headline)
                            .monospacedDigit()
                            .frame(minWidth: 20)
                    }
                }
                .padding()
                
                // Validation message
                if let message = locationValidationMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                
                Divider()
                
                // Row 2: Expiration
                HStack {
                    Toggle("Expiration", isOn: $showingDatePicker)
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .ppPurple))
                    
                    Text("Expiration")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if showingDatePicker {
                        DatePicker("", selection: $expirationDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .padding()
            }
            .background(Color.gray.opacity(0.05))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // CTAs
            VStack(spacing: 12) {
                // Primary: Add & Keep Scanning
                Button(action: {
                    Task { await addItem(keepScanning: true) }
                }) {
                    HStack {
                        Image(systemName: "barcode.viewfinder")
                        Text("Add & Keep Scanning")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.ppPurple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(isAddingCustom || (isProductNotFound && !canAddCustomProduct))
                
                HStack(spacing: 12) {
                    // Secondary: Add (and close)
                    Button(action: {
                        Task { await addItem(keepScanning: false) }
                    }) {
                        Text("Add")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.ppPurple.opacity(0.1))
                            .foregroundColor(.ppPurple)
                            .cornerRadius(12)
                    }
                    .disabled(isAddingCustom || (isProductNotFound && !canAddCustomProduct))
                    
                    // Tertiary: Cancel
                    Button(action: {
                        resetScannerState()
                    }) {
                        Text("Cancel")
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .foregroundColor(.primary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    private var isProductNotFound: Bool {
        if let result = lookupResult {
            return !result.found
        }
        return false
    }
    
    private var canAddCustomProduct: Bool {
        !customName.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var locationValidationMessage: String? {
        return nil // Location is now always valid (never nil)
    }
    
    private func resetScannerState() {
        scannedCode = nil
        lookupResult = nil
        quantity = 1
        showingDatePicker = false
        customName = ""
        customBrand = ""
        isEditingFoundProduct = false
        editedName = ""
        editedBrand = ""
        isScanning = true // Resume scanning
    }
    
    private func addItem(keepScanning: Bool) async {
        guard let code = scannedCode else { return }
        
        if isProductNotFound {
            await addCustomProduct(upc: code, keepScanning: keepScanning)
        } else {
            await addExistingProduct(upc: code, keepScanning: keepScanning)
        }
    }
    
    private func addCustomProduct(upc: String, keepScanning: Bool) async {
        isAddingCustom = true
        
        do {
            // Create the custom product with the scanned UPC
            let product = try await APIService.shared.createProduct(
                upc: upc,
                name: customName.trimmingCharacters(in: .whitespaces),
                brand: customBrand.isEmpty ? nil : customBrand.trimmingCharacters(in: .whitespaces),
                description: nil,
                category: nil
            )
            
            // Add to inventory
            guard !selectedLocationId.isEmpty else {
                viewModel.errorMessage = "Please select a location"
                isAddingCustom = false
                return
            }
            
            UserPreferences.shared.lastUsedLocationId = selectedLocationId
            
            _ = await viewModel.addCustomItem(
                product: product,
                quantity: quantity,
                expirationDate: showingDatePicker ? expirationDate : nil,
                locationId: selectedLocationId
            )
            
            let productName = customName.trimmingCharacters(in: .whitespaces)
            onItemAdded?("Added \(productName)")
            
            if keepScanning {
                resetScannerState()
            } else {
                isPresented = false
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
            HapticService.shared.error()
        }
        
        isAddingCustom = false
    }
    
    private func addExistingProduct(upc: String, keepScanning: Bool) async {
        guard !selectedLocationId.isEmpty else { return }
        UserPreferences.shared.lastUsedLocationId = selectedLocationId
        
        // Check if user edited the product
        if !editedName.isEmpty {
            // User edited - create/update custom product with edited values
            isAddingCustom = true
            do {
                let product = try await APIService.shared.createProduct(
                    upc: upc,
                    name: editedName.trimmingCharacters(in: .whitespaces),
                    brand: editedBrand.isEmpty ? nil : editedBrand.trimmingCharacters(in: .whitespaces),
                    description: nil,
                    category: lookupResult?.product?.category
                )
                
                _ = await viewModel.addCustomItem(
                    product: product,
                    quantity: quantity,
                    expirationDate: showingDatePicker ? expirationDate : nil,
                    locationId: selectedLocationId
                )
                
                onItemAdded?(editedName)
                
                if keepScanning {
                    resetScannerState()
                } else {
                    isPresented = false
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
            isAddingCustom = false
        } else {
            // Use original product
            let response = await viewModel.quickAdd(
                upc: upc,
                quantity: quantity,
                expirationDate: showingDatePicker ? expirationDate : nil,
                locationId: selectedLocationId
            )
            
            if response?.requiresCustomProduct == true {
                // This shouldn't happen now since we handle it inline
                pendingUPC = upc
                showingCustomProductForm = true
            } else {
                let productName = lookupResult?.product?.name ?? "Item"
                
                if let action = response?.action, action == "updated", let item = response?.item {
                    onItemAdded?("Now \(item.quantity) in Pantry")
                } else {
                    onItemAdded?("Added \(productName)")
                }
                
                if keepScanning {
                    resetScannerState()
                } else {
                    isPresented = false
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
    
    private func lookupProduct(upc: String) {
        isLookingUp = true
        Task {
            do {
                let result = try await APIService.shared.lookupUPC(upc)
                await MainActor.run {
                    lookupResult = result
                    isLookingUp = false
                    
                    // Check for existing item in local inventory
                    if let product = result.product {
                        existingItem = viewModel.items.first { $0.productId == product.id || $0.productUpc == upc }
                        if let existing = existingItem {
                            // Pre-select location if exists
                            if let locId = existing.locationId {
                                selectedLocationId = locId
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    lookupResult = UPCLookupResponse(found: false, product: nil, source: nil, upc: upc, requiresCustomProduct: true)
                    isLookingUp = false
                }
            }
        }
    }
}
