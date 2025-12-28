import SwiftUI

struct InventoryListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = InventoryViewModel()
    
    @State private var showingScanner = false
    @State private var showingAddCustom = false
    @State private var showingSettings = false
    @State private var showingPaywall = false
    @State private var editingItem: InventoryItem?
    @State private var scannedUPC: String?
    @State private var searchText = ""
    @State private var selectedFilter: InventoryFilter = .all
    
    // Toast state
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastType: ToastView.ToastType = .success
    
    enum InventoryFilter: String, CaseIterable {
        case all = "All"
        case expiringSoon = "Expiring Soon"
        case expired = "Expired"
    }
    
    var filteredItems: [InventoryItem] {
        var items: [InventoryItem]
        
        switch selectedFilter {
        case .all:
            items = viewModel.items
        case .expiringSoon:
            items = viewModel.items.filter { $0.isExpiringSoon }
        case .expired:
            items = viewModel.items.filter { $0.isExpired }
        }
        
        if searchText.isEmpty {
            return items
        }
        
        return items.filter { item in
            item.displayName.localizedCaseInsensitiveContains(searchText) ||
            (item.productBrand?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            (item.productUpc?.contains(searchText) ?? false)
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView("Loading inventory...")
                } else if viewModel.items.isEmpty {
                    emptyStateView
                } else {
                    inventoryListContent
                }
            }
            .navigationTitle("Pantry (\(viewModel.items.count))")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "person.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { 
                            if checkLimit() { showingAddCustom = true }
                        }) {
                            Image(systemName: "plus")
                        }
                        
                        Button(action: { 
                            if checkLimit() { showingScanner = true }
                        }) {
                            Image(systemName: "barcode.viewfinder")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search items")
            .refreshable {
                print("🔄 [InventoryListView] User triggered refresh")
                // 1. Upload pending changes first so they are included in the sync
                await ActionQueueService.shared.processQueue(modelContext: modelContext)
                
                // 2. Fetch latest data (which should now include our uploads)
                do {
                    try await SyncService.shared.syncFromRemote(modelContext: modelContext)
                    print("✅ [InventoryListView] Sync completed successfully")
                } catch {
                    print("❌ [InventoryListView] Sync failed: \(error)")
                }
                
                // 3. Reload view model
                await viewModel.loadInventory()
            }
            .sheet(isPresented: $showingScanner) {
                if UserPreferences.shared.useSmartScanner {
                    SmartScannerView(isPresented: $showingScanner, onItemScanned: { name, upc, date in
                        Task {
                            let success = await viewModel.addSmartItem(name: name, upc: upc, expirationDate: date)
                            if success {
                                showSuccessToast("Added \(name) to pantry!")
                            } else {
                                // Error is handled in viewModel.errorMessage
                            }
                        }
                    })
                } else {
                    ScannerSheet(viewModel: $viewModel, isPresented: $showingScanner, onItemAdded: { message in
                        showSuccessToast(message.contains("Added") || message.contains("Updated") ? message : "Added \(message) to pantry!")
                    })
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomItemView(viewModel: $viewModel, isPresented: $showingAddCustom, onItemAdded: { name in
                    showSuccessToast("Added \(name) to pantry!")
                })
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView()
            }
            .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
                Button("OK") { 
                    if viewModel.errorMessage?.contains("limit reached") == true {
                        showingPaywall = true
                    }
                    viewModel.errorMessage = nil 
                }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .task {
                print("🚀 [InventoryListView] View loaded, starting initial sync sequence")
                viewModel.setContext(modelContext)
                await viewModel.loadInventory()
                await viewModel.loadLocations()
                
                // Initial sync sequence
                await ActionQueueService.shared.processQueue(modelContext: modelContext)
                do {
                    try await SyncService.shared.syncFromRemote(modelContext: modelContext)
                    print("✅ [InventoryListView] Initial sync completed")
                } catch {
                    print("❌ [InventoryListView] Initial sync failed: \(error)")
                }
                await viewModel.loadInventory()
            }
            .onReceive(NotificationCenter.default.publisher(for: .showPaywall)) { _ in
                showingPaywall = true
                // Refresh inventory to revert local optimistic changes
                Task { await viewModel.loadInventory() }
            }
            .toast(isShowing: $showToast, message: toastMessage, type: toastType)
        }
    }
    
    private func showSuccessToast(_ message: String) {
        toastMessage = message
        toastType = .success
        HapticService.shared.success()
        withAnimation {
            showToast = true
        }
    }
    
    private func checkLimit() -> Bool {
        let isPremium = authViewModel.currentHousehold?.isPremium ?? false
        let count = viewModel.items.count
        
        if !isPremium && count >= 3 {
            showingPaywall = true
            return false
        }
        return true
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.ppGreen)
            
            Text("No items in your pantry")
                .font(.headline)
            
            Text("Scan a barcode or add items manually")
                .foregroundColor(.secondary)
            
            HStack(spacing: 16) {
                Button(action: { 
                    if checkLimit() { showingScanner = true }
                }) {
                    Label("Scan", systemImage: "barcode.viewfinder")
                }
                .buttonStyle(.ppPrimary)
                .frame(width: 140)
                
                Button(action: { 
                    if checkLimit() { showingAddCustom = true }
                }) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.ppSecondary)
                .frame(width: 140)
            }
        }
        .padding()
    }
    
    private var inventoryListContent: some View {
        VStack(spacing: 0) {
            // Filter picker
            Picker("Filter", selection: $selectedFilter) {
                ForEach(InventoryFilter.allCases, id: \.self) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            
            // Success message
            if let success = viewModel.successMessage {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.ppGreen)
                    Text(success)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.ppGreen.opacity(0.15))
                .cornerRadius(8)
                .padding(.horizontal)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        viewModel.successMessage = nil
                    }
                }
            }
            
            List {
                ForEach(filteredItems) { item in
                    InventoryItemRow(item: item, viewModel: $viewModel, onEdit: {
                        editingItem = item
                    })
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await viewModel.deleteItem(id: filteredItems[index].id)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
        .sheet(item: $editingItem) { item in
            EditItemView(item: item, viewModel: $viewModel, editingItem: $editingItem)
        }
    }
}

struct InventoryItemRow: View {
    let item: InventoryItem
    @Binding var viewModel: InventoryViewModel
    var onEdit: () -> Void = {}
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        Button(action: onEdit) {
            HStack(spacing: 12) {
                // Product image placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "shippingbox")
                        .foregroundColor(.gray)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if let brand = item.productBrand {
                        Text(brand)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let expDate = item.expirationDate {
                        HStack(spacing: 4) {
                            Image(systemName: item.isExpired ? "exclamationmark.triangle.fill" : (item.isExpiringSoon ? "clock.fill" : "calendar"))
                                .font(.caption2)
                            Text(formatDate(expDate))
                                .font(.caption)
                        }
                        .foregroundColor(item.isExpired ? .ppDanger : (item.isExpiringSoon ? .ppOrange : .ppSecondaryText))
                    }
                }
                
                Spacer()
                
                // Quantity controls
                HStack(spacing: 8) {
                    Button(action: {
                        if item.quantity <= 1 {
                            showDeleteConfirmation = true
                            HapticService.shared.warning()
                        } else {
                            HapticService.shared.lightImpact()
                            Task { await viewModel.adjustQuantity(id: item.id, adjustment: -1) }
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.ppOrange)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(item.quantity)")
                        .font(.headline)
                        .foregroundColor(.ppPurple)
                        .frame(minWidth: 30)
                    
                    Button(action: {
                        HapticService.shared.lightImpact()
                        Task { await viewModel.adjustQuantity(id: item.id, adjustment: 1) }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.ppGreen)
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .buttonStyle(.plain)
        .foregroundColor(.primary)
        .padding(.vertical, 4)
        .alert("Remove Item?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                Task { await viewModel.adjustQuantity(id: item.id, adjustment: -1) }
            }
        } message: {
            Text("This will remove \"\(item.displayName)\" from your pantry.")
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateString) else { return dateString }
        
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

struct ScannerSheet: View {
    @Binding var viewModel: InventoryViewModel
    @Binding var isPresented: Bool
    var onItemAdded: ((String) -> Void)?
    
    @State private var scannedCode: String?
    @State private var showingDatePicker = false
    @State private var expirationDate = Date()
    @State private var quantity = 1
    @State private var showingCustomProductForm = false
    @State private var pendingUPC: String?
    @State private var lookupResult: UPCLookupResponse?
    @State private var isLookingUp = false
    @State private var selectedLocationId: String? = UserPreferences.shared.lastUsedLocationId
    
    // Custom product fields for inline entry
    @State private var customName = ""
    @State private var customBrand = ""
    @State private var isAddingCustom = false
    
    // Edit mode for found products
    @State private var isEditingFoundProduct = false
    @State private var editedName = ""
    @State private var editedBrand = ""
    
    @State private var existingItem: InventoryItem?
    
    var body: some View {
        NavigationStack {
            VStack {
                if let code = scannedCode {
                    scannedResultView(code: code)
                } else {
                    BarcodeScannerView(scannedCode: $scannedCode, isPresented: .constant(true)) { code in
                        scannedCode = code
                        HapticService.shared.mediumImpact()
                        lookupProduct(upc: code)
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
    
    private func scannedResultView(code: String) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.ppGreen)
                
                Text("Barcode Scanned")
                    .font(.headline)
                
                Text(code)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                
                // Existing item alert
                if let existing = existingItem {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.ppPurple)
                        VStack(alignment: .leading) {
                            Text("Item in Inventory")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text("You have \(existing.quantity) in \(existing.locationName ?? "storage")")
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.ppPurple.opacity(0.1))
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
                
                // Product details card
                productDetailsCard
                
                // Quantity and expiration controls
                VStack(spacing: 16) {
                    // Location picker
                    if viewModel.locations.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.ppOrange)
                            Text("Set up locations in Settings first")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Location")
                                    .font(.subheadline)
                                    .foregroundColor(selectedLocationId == nil ? .red : .primary)
                                if selectedLocationId == nil {
                                    Text("(Required)")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                            Picker("Location", selection: $selectedLocationId) {
                                Text("Select Location").tag(nil as String?)
                                ForEach(viewModel.locations) { location in
                                    Text(location.fullPath).tag(location.id as String?)
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(8)
                            .background(selectedLocationId == nil ? Color.red.opacity(0.1) : Color.clear)
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(selectedLocationId == nil ? Color.red.opacity(0.5) : Color.clear, lineWidth: 1)
                            )
                        }
                        .padding(.horizontal)
                    }
                    
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...99)
                        .padding(.horizontal)
                    
                    Toggle("Add expiration date", isOn: $showingDatePicker)
                        .padding(.horizontal)
                    
                    if showingDatePicker {
                        DatePicker("Expiration Date", selection: $expirationDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .padding(.horizontal)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Action buttons
                HStack(spacing: 16) {
                    Button("Scan Again") {
                        scannedCode = nil
                        lookupResult = nil
                    }
                    .buttonStyle(.ppSecondary)
                    .frame(width: 130)
                    
                    if isProductNotFound {
                        // Add custom product button
                        Button(isAddingCustom ? "Adding..." : "Add to Pantry") {
                            Task {
                                await addCustomProduct(upc: code)
                            }
                        }
                        .buttonStyle(.ppPrimary)
                        .frame(width: 150)
                        .disabled(!canAddCustomProduct || isAddingCustom || selectedLocationId == nil)
                    } else {
                        // Add existing product button
                        Button("Add to Pantry") {
                            Task {
                                guard let locationId = selectedLocationId else { return }
                                UserPreferences.shared.lastUsedLocationId = locationId
                                
                                // Check if user edited the product
                                if !editedName.isEmpty {
                                    // User edited - create/update custom product with edited values
                                    isAddingCustom = true
                                    do {
                                        let product = try await APIService.shared.createProduct(
                                            upc: code,
                                            name: editedName.trimmingCharacters(in: .whitespaces),
                                            brand: editedBrand.isEmpty ? nil : editedBrand.trimmingCharacters(in: .whitespaces),
                                            description: nil,
                                            category: lookupResult?.product?.category
                                        )
                                        
                                        _ = try await APIService.shared.addToInventory(
                                            productId: product.id,
                                            quantity: quantity,
                                            expirationDate: showingDatePicker ? formatDate(expirationDate) : nil,
                                            notes: nil,
                                            locationId: locationId
                                        )
                                        
                                        await viewModel.loadInventory()
                                        isPresented = false
                                        onItemAdded?(editedName)
                                    } catch {
                                        viewModel.errorMessage = error.localizedDescription
                                    }
                                    isAddingCustom = false
                                } else {
                                    // Use original product
                                    let response = await viewModel.quickAdd(
                                        upc: code,
                                        quantity: quantity,
                                        expirationDate: showingDatePicker ? expirationDate : nil,
                                        locationId: locationId
                                    )
                                    
                                    if response?.requiresCustomProduct == true {
                                        // This shouldn't happen now since we handle it inline
                                        pendingUPC = code
                                        showingCustomProductForm = true
                                    } else {
                                        let productName = lookupResult?.product?.name ?? "Item"
                                        isPresented = false
                                        
                                        if let action = response?.action, action == "updated" {
                                            onItemAdded?("Updated \(productName)")
                                        } else {
                                            onItemAdded?("Added \(productName)")
                                        }
                                    }
                                }
                            }
                        }
                        .buttonStyle(.ppPrimary)
                        .frame(width: 150)
                        .disabled(selectedLocationId == nil || isAddingCustom)
                    }
                }
                
                Spacer()
            }
            .padding(.top, 30)
        }
    }
    
    @ViewBuilder
    private var productDetailsCard: some View {
        VStack(spacing: 12) {
            if isLookingUp {
                ProgressView()
                    .padding()
                Text("Looking up product...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else if let result = lookupResult {
                if result.found, let product = result.product {
                    // Product found - show details with edit option
                    VStack(spacing: 12) {
                        HStack(spacing: 16) {
                            // Product image placeholder
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.ppPurple.opacity(0.1))
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: "shippingbox.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.ppPurple)
                            }
                            
                            if isEditingFoundProduct {
                                // Editable fields
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("Product Name", text: $editedName)
                                        .textFieldStyle(.roundedBorder)
                                    
                                    TextField("Brand (optional)", text: $editedBrand)
                                        .textFieldStyle(.roundedBorder)
                                }
                            } else {
                                // Display mode
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(editedName.isEmpty ? product.name : editedName)
                                        .font(.headline)
                                        .lineLimit(2)
                                    
                                    let displayBrand = editedBrand.isEmpty ? product.brand : editedBrand
                                    if let brand = displayBrand, !brand.isEmpty {
                                        Text(brand)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if let category = product.category, !category.isEmpty {
                                        Text(category)
                                            .font(.caption)
                                            .foregroundColor(.ppPurple)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(Color.ppPurple.opacity(0.1))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Edit/Done button
                            Button {
                                if isEditingFoundProduct {
                                    // Done editing
                                    isEditingFoundProduct = false
                                } else {
                                    // Start editing - populate fields
                                    editedName = product.name
                                    editedBrand = product.brand ?? ""
                                    isEditingFoundProduct = true
                                }
                            } label: {
                                Image(systemName: isEditingFoundProduct ? "checkmark.circle.fill" : "pencil.circle")
                                    .font(.system(size: 24))
                                    .foregroundColor(.ppPurple)
                            }
                        }
                        
                        if isEditingFoundProduct {
                            Text("Edit the product details before adding to your pantry")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding()
                    .background(Color.ppGreen.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.ppGreen.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    // Product not found - show inline custom product form
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 24))
                                .foregroundColor(.ppOrange)
                            
                            Text("Product Not Found")
                                .font(.headline)
                            
                            Spacer()
                        }
                        
                        Text("Enter the product details to add it to your pantry.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        TextField("Product Name *", text: $customName)
                            .textFieldStyle(.roundedBorder)
                        
                        TextField("Brand (optional)", text: $customBrand)
                            .textFieldStyle(.roundedBorder)
                    }
                    .padding()
                    .background(Color.ppOrange.opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.ppOrange.opacity(0.3), lineWidth: 1)
                    )
                }
            }
        }
        .padding(.horizontal)
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
    
    private func addCustomProduct(upc: String) async {
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
            guard let locationId = selectedLocationId else {
                viewModel.errorMessage = "Please select a location"
                isAddingCustom = false
                return
            }
            
            UserPreferences.shared.lastUsedLocationId = locationId
            
            _ = try await APIService.shared.addToInventory(
                productId: product.id,
                quantity: quantity,
                expirationDate: showingDatePicker ? formatDate(expirationDate) : nil,
                notes: nil,
                locationId: locationId
            )
            
            await viewModel.loadInventory()
            let productName = customName.trimmingCharacters(in: .whitespaces)
            isPresented = false
            onItemAdded?(productName)
        } catch {
            viewModel.errorMessage = error.localizedDescription
            HapticService.shared.error()
        }
        
        isAddingCustom = false
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

struct AddCustomItemView: View {
    @Binding var viewModel: InventoryViewModel
    @Binding var isPresented: Bool
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
    @State private var selectedLocationId: String? = UserPreferences.shared.lastUsedLocationId
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Product Info") {
                    TextField("Product Name *", text: $name)
                    TextField("Brand", text: $brand)
                    
                    HStack {
                        TextField("UPC (optional)", text: $upc)
                        
                        Button(action: { showingScanner = true }) {
                            Image(systemName: "barcode.viewfinder")
                                .foregroundColor(.ppPurple)
                        }
                    }
                }
                
                Section("Location") {
                    if viewModel.locations.isEmpty {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.ppOrange)
                            Text("Set up locations in Settings first")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Picker("Storage Location *", selection: $selectedLocationId) {
                            Text("Select Location").tag(nil as String?)
                            ForEach(viewModel.locations) { location in
                                Text(location.fullPath).tag(location.id as String?)
                            }
                        }
                    }
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
                    .disabled(name.isEmpty || isLoading || selectedLocationId == nil)
                }
            }
            .onAppear {
                if let upc = prefilledUPC {
                    self.upc = upc
                }
            }
            .sheet(isPresented: $showingScanner) {
                UPCScannerSheet(scannedUPC: $upc, isPresented: $showingScanner)
            }
        }
    }
    
    private func saveItem() async {
        isLoading = true
        
        guard let locationId = selectedLocationId else {
            viewModel.errorMessage = "Please select a location"
            isLoading = false
            return
        }
        
        UserPreferences.shared.lastUsedLocationId = locationId
        
        do {
            let product = try await APIService.shared.createProduct(
                upc: upc.isEmpty ? nil : upc,
                name: name,
                brand: brand.isEmpty ? nil : brand,
                description: nil,
                category: nil
            )
            
            let success = await viewModel.addItem(
                productId: product.id,
                quantity: quantity,
                expirationDate: showingDatePicker ? expirationDate : nil,
                locationId: locationId
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

struct EditItemView: View {
    let item: InventoryItem
    @Binding var viewModel: InventoryViewModel
    @Binding var editingItem: InventoryItem?
    
    @State private var quantity: Int
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    @State private var notes: String
    @State private var selectedLocationId: String?
    @State private var isLoading = false
    
    init(item: InventoryItem, viewModel: Binding<InventoryViewModel>, editingItem: Binding<InventoryItem?>) {
        self.item = item
        self._viewModel = viewModel
        self._editingItem = editingItem
        self._quantity = State(initialValue: item.quantity)
        self._hasExpiration = State(initialValue: item.expirationDate != nil)
        self._notes = State(initialValue: item.notes ?? "")
        self._selectedLocationId = State(initialValue: item.locationId)
        
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
                            Text("Select Location").tag(nil as String?)
                            ForEach(viewModel.locations) { location in
                                Text(location.fullPath).tag(location.id as String?)
                            }
                        }
                    }
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
                    .disabled(isLoading)
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
        isLoading = true
        
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

// Simple UPC Scanner for just capturing a barcode
struct UPCScannerSheet: View {
    @Binding var scannedUPC: String
    @Binding var isPresented: Bool
    
    @State private var tempCode: String?
    
    var body: some View {
        NavigationStack {
            VStack {
                if let code = tempCode {
                    VStack(spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.ppGreen)
                        
                        Text("Barcode Scanned")
                            .font(.headline)
                        
                        Text(code)
                            .font(.title2)
                            .fontWeight(.medium)
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        
                        HStack(spacing: 16) {
                            Button("Scan Again") {
                                tempCode = nil
                            }
                            .buttonStyle(.ppSecondary)
                            
                            Button("Use This Code") {
                                scannedUPC = code
                                isPresented = false
                            }
                            .buttonStyle(.ppPrimary)
                        }
                    }
                    .padding()
                } else {
                    BarcodeScannerView(scannedCode: $tempCode, isPresented: .constant(true)) { code in
                        tempCode = code
                    }
                }
            }
            .navigationTitle("Scan UPC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

#Preview {
    InventoryListView()
        .environment(AuthViewModel())
}
