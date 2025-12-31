import SwiftUI

struct InventoryListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = InventoryViewModel()
    @State private var groceryViewModel = GroceryViewModel()
    
    @State private var showingScanner = false
    @State private var showingAddCustom = false
    @State private var showingSettings = false
    @State private var showingPaywall = false
    @State private var editingItem: InventoryItem?
    @State private var scannedUPC: String?
    @State private var searchText = ""
    @State private var selectedFilter: InventoryFilter = .all
    
    // Grocery add confirmation (for Free users when last item removed)
    @State private var showGroceryPrompt = false
    @State private var pendingGroceryItem: String?
    
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
            List {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Loading inventory...")
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                } else if viewModel.items.isEmpty {
                    Section {
                        emptyStateContent
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    inventoryListSections
                }
            }
            .listStyle(.plain)
            .searchable(text: $searchText, prompt: "Search items")
            .navigationTitle("Pantry (\(viewModel.items.count))")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "person.circle")
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        Button(action: { 
                            if checkLimit() { showingAddCustom = true }
                        }) {
                            Image(systemName: "plus")
                        }
                        
                        Button(action: { 
                            if checkLimit() { showingScanner = true }
                        }) {
                            Image(systemName: "barcode.viewfinder")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
            .refreshable {
                print("🔄 [InventoryListView] Pull-to-refresh triggered")
                await SyncCoordinator.shared.syncNow(
                    householdId: authViewModel.currentUser?.householdId,
                    modelContext: modelContext,
                    reason: .pullToRefresh
                )
                await viewModel.loadInventory(withLoadingState: false)
                await viewModel.loadLocations()
            }
            .sheet(isPresented: $showingScanner) {
                if UserPreferences.shared.useSmartScanner {
                    SmartScannerView(isPresented: $showingScanner, onItemScanned: { name, upc, date in
                        Task {
                            let success = await viewModel.addSmartItem(name: name, upc: upc, expirationDate: date)
                            if success {
                                ToastCenter.shared.show("Added \(name) to pantry!", type: .success)
                                // Auto-remove from grocery if item was restocked
                                await tryAutoRemoveFromGrocery(name: name, upc: upc)
                            } else {
                                // Error is handled in viewModel.errorMessage
                            }
                        }
                    })
                    .environment(authViewModel)
                    .presentationDetents([.large])
                } else {
                    ScannerSheet(viewModel: $viewModel, isPresented: $showingScanner, onItemAdded: { message in
                        ToastCenter.shared.show(message.contains("Added") || message.contains("Updated") ? message : "Added \(message) to pantry!", type: .success)
                        // Trigger auto-remove check after scanner success
                        Task {
                            await checkRecentlyAddedForGroceryRemoval()
                        }
                    })
                    .environment(authViewModel)
                    .presentationDetents([.large])
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomItemView(viewModel: $viewModel, isPresented: $showingAddCustom, onItemAdded: { name in
                    ToastCenter.shared.show("Added \(name) to pantry!", type: .success)
                    // Auto-remove from grocery if item was restocked
                    Task {
                        await tryAutoRemoveFromGrocery(name: name, upc: nil)
                    }
                })
                .environment(authViewModel)
                .presentationDetents([.large])
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(limit: authViewModel.freeLimit)
                    .presentationDetents([.large])
            }
            .sheet(item: $editingItem) { item in
                EditItemView(item: item, viewModel: $viewModel, editingItem: $editingItem)
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
                groceryViewModel.setModelContext(modelContext)
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
                // Reload without triggering full loading state to avoid flash
                await viewModel.loadInventory(withLoadingState: false)
                await viewModel.loadLocations()
            }
            .onChange(of: scenePhase) { oldPhase, newPhase in
                if newPhase == .active {
                    print("🔄 [InventoryListView] App became active, syncing...")
                    Task {
                        await ActionQueueService.shared.processQueue(modelContext: modelContext)
                        SyncCoordinator.shared.requestSync(
                            householdId: authViewModel.currentUser?.householdId,
                            modelContext: modelContext,
                            reason: .appActive
                        )
                        await viewModel.loadInventory(withLoadingState: false)
                        await viewModel.loadLocations()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showPaywall)) { _ in
                // Only show paywall if we're not already showing settings (which handles its own paywall)
                if !showingSettings {
                    showingPaywall = true
                    // Refresh inventory to revert local optimistic changes
                    Task { await viewModel.loadInventory() }
                }
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
    
    private func checkLimit() -> Bool {
        let isPremium = authViewModel.currentHousehold?.isPremium ?? false
        let count = viewModel.items.count
        
        if !isPremium && count >= authViewModel.freeLimit {
            showingPaywall = true
            return false
        }
        return true
    }
    
    // MARK: - Polling
    
    
    private func handleDecrement(item: InventoryItem) async {
        print("🛒 [GroceryLogic] handleDecrement called for: \(item.displayName), current qty: \(item.quantity)")
        
        // Decrement will happen, so check if THIS decrement makes it zero
        let willBeZero = item.quantity == 1
        
        if willBeZero {
            print("🛒 [GroceryLogic] This decrement will make quantity zero - treating as last item")
            await handleItemRemoval(item: item)
        } else {
            print("🛒 [GroceryLogic] Regular decrement, quantity will be: \(item.quantity - 1)")
            await viewModel.adjustQuantity(id: item.id, adjustment: -1)
            SyncCoordinator.shared.requestSync(
                householdId: authViewModel.currentUser?.householdId,
                modelContext: modelContext,
                reason: .afterAction
            )
        }
    }
    
    private func handleItemRemoval(item: InventoryItem) async {
        let isPremium = authViewModel.currentHousehold?.isPremiumActive ?? false
        let itemName = item.displayName
        let wasLastItem = item.quantity == 1
        
        print("🛒 [GroceryLogic] handleItemRemoval called")
        print("🛒 [GroceryLogic] - Item: \(itemName), Quantity: \(item.quantity)")
        print("🛒 [GroceryLogic] - isPremium: \(isPremium)")
        print("🛒 [GroceryLogic] - wasLastItem: \(wasLastItem)")
        
        // Perform the deletion
        await viewModel.adjustQuantity(id: item.id, adjustment: -1)
        SyncCoordinator.shared.requestSync(
            householdId: authViewModel.currentUser?.householdId,
            modelContext: modelContext,
            reason: .afterAction
        )
        
        // Trigger grocery logic if this was the last item
        if wasLastItem {
            print("🛒 [GroceryLogic] Last item detected, triggering handleItemHitZero")
            await handleItemHitZero(itemName: itemName, isPremium: isPremium)
        } else {
            print("🛒 [GroceryLogic] Not last item, no grocery action")
        }
    }
    
    private func handleItemHitZero(itemName: String, isPremium: Bool) async {
        print("🛒 [GroceryLogic] handleItemHitZero called")
        print("🛒 [GroceryLogic] - itemName: \(itemName)")
        print("🛒 [GroceryLogic] - isPremium: \(isPremium)")
        
        // Show confirmation prompt for ALL users (Premium and Free)
        print("🛒 [GroceryLogic] Showing confirmation prompt for: \(itemName)")
        pendingGroceryItem = itemName
        showGroceryPrompt = true
    }
    
    private func addToGroceryList(_ itemName: String) async {
        print("🛒 [GroceryAdd] Starting addToGroceryList for: \(itemName)")
        do {
            _ = try await APIService.shared.addGroceryItem(name: itemName)
            print("🛒 [GroceryAdd] ✅ Successfully added: \(itemName)")
            ToastCenter.shared.show("✓ Added to grocery list", type: .success)
        } catch let error as APIError {
            print("🛒 [GroceryAdd] ❌ APIError: \(error)")
            ToastCenter.shared.show("Failed to add to grocery list", type: .error)
        } catch {
            print("🛒 [GroceryAdd] ❌ Unknown error: \(error)")
            ToastCenter.shared.show("Failed to add to grocery list", type: .error)
        }
    }
    
    /// Attempts to auto-remove from grocery list when inventory is restocked
    private func attemptGroceryAutoRemove(forItem item: InventoryItem) async {
        guard item.quantity > 0 else { return }
        
        let removed = await groceryViewModel.attemptAutoRemove(
            upc: item.productUpc,
            name: item.productName ?? item.displayName,
            brand: item.productBrand
        )
        
        if removed {
            let displayName = item.displayName
            ToastCenter.shared.show("Removed \(displayName) from grocery list", type: .info)
        }
    }
    
    /// Try auto-remove using name and UPC
    private func tryAutoRemoveFromGrocery(name: String, upc: String?) async {
        let removed = await groceryViewModel.attemptAutoRemove(
            upc: upc,
            name: name,
            brand: nil
        )
        
        if removed {
            ToastCenter.shared.show("Removed from grocery list", type: .info)
        }
    }
    
    /// Check recently added items (fallback for scanner sheet)
    private func checkRecentlyAddedForGroceryRemoval() async {
        // After a successful add, check the most recent items in inventory
        // This is a fallback since scanner doesn't give us item details
        guard let recentItem = viewModel.items.first else { return }
        await attemptGroceryAutoRemove(forItem: recentItem)
    }
    
    private var emptyStateContent: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 60)
            
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.ppGreen)
            
            Text("No items in your pantry")
                .font(.headline)
            
            Text("Scan a barcode or add items manually")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
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
            
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
    
    private var inventoryListSections: some View {
        Group {
            // Filter picker section
            Section {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(InventoryFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            
            // Success message
            if let success = viewModel.successMessage {
                Section {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.ppGreen)
                        Text(success)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.ppGreen.opacity(0.15))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        viewModel.successMessage = nil
                    }
                }
            }
            
            // Inventory items
            Section {
                ForEach(filteredItems) { item in
                    InventoryItemRow(
                        item: item,
                        viewModel: $viewModel,
                        onEdit: {
                            editingItem = item
                        },
                        onRemove: { item in
                            await handleItemRemoval(item: item)
                        },
                        onDecrement: { item in
                            await handleDecrement(item: item)
                        }
                    )
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet {
                            await viewModel.deleteItem(id: filteredItems[index].id)
                        }
                    }
                }
            }
        }
    }
}

struct InventoryItemRow: View {
    let item: InventoryItem
    @Binding var viewModel: InventoryViewModel
    var onEdit: () -> Void = {}
    var onRemove: (InventoryItem) async -> Void // Handler for full removal
    var onDecrement: (InventoryItem) async -> Void // Handler for decrement (may trigger grocery logic)
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
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let locationName = item.locationName {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.caption2)
                            Text(locationName)
                                .font(.caption)
                        }
                        .foregroundStyle(.tertiary)
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
                            Task { await onDecrement(item) }
                        }
                    }) {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(Color(uiColor: .systemGray4))
                            .font(.title2)
                    }
                    .buttonStyle(.plain)
                    
                    Text("\(item.quantity)")
                        .font(.headline)
                        .foregroundColor(.ppPurple)
                        .frame(minWidth: 30)
                    
                    Button(action: {
                        HapticService.shared.lightImpact()
                        Task {
                            await viewModel.adjustQuantity(id: item.id, adjustment: 1)
                        }
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
                Task {
                    await onRemove(item)
                }
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
                    TextField("Brand", text: $brand)
                    
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

// Simple UPC Scanner for just capturing a barcode
struct UPCScannerSheet: View {
    @Binding var scannedUPC: String
    @Binding var isPresented: Bool
    
    @State private var tempCode: String?
    @State private var isScanning = true
    
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
                                isScanning = true
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
                    BarcodeScannerView(scannedCode: $tempCode, isPresented: .constant(true), isScanning: $isScanning) { code in
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
