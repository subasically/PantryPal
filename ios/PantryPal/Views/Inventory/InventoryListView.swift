import SwiftUI
import SwiftData

struct InventoryListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = InventoryViewModel()
    @State private var groceryViewModel = GroceryViewModel()
    
    // Sync status tracking
    @State private var showSyncDetail = false
    @State private var pendingActionsCount = 0
    
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
        // First apply filter
        let baseItems: [InventoryItem]
        switch selectedFilter {
        case .all:
            baseItems = viewModel.items
        case .expiringSoon:
            baseItems = viewModel.items.filter { item in
                item.isExpiringSoon
            }
        case .expired:
            baseItems = viewModel.items.filter { item in
                item.isExpired
            }
        }
        
        // Then apply search
        guard !searchText.isEmpty else {
            return baseItems
        }
        
        return baseItems.filter { item in
            matchesSearch(item: item, searchText: searchText)
        }
    }
    
    private func matchesSearch(item: InventoryItem, searchText: String) -> Bool {
        let searchLower = searchText.lowercased()
        
        // Check name
        let nameMatch = item.displayName.lowercased().contains(searchLower)
        if nameMatch { return true }
        
        // Check brand
        if let brand = item.productBrand {
            let brandMatch = brand.lowercased().contains(searchLower)
            if brandMatch { return true }
        }
        
        // Check UPC
        if let upc = item.productUpc {
            let upcMatch = upc.contains(searchText)
            if upcMatch { return true }
        }
        
        return false
    }
    
    private var inventoryList: some View {
        List {
            if viewModel.isLoading && viewModel.items.isEmpty {
                loadingSection
            } else if viewModel.items.isEmpty {
                emptySection
            } else {
                inventoryListSections
            }
        }
        .accessibilityIdentifier("inventory.list")
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search items")
    }
    
    private var loadingSection: some View {
        Section {
            HStack {
                Spacer()
                ProgressView("Loading inventory...")
                Spacer()
            }
        }
        .listRowBackground(Color.clear)
    }
    
    private var emptySection: some View {
        Section {
            emptyStateContent
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
    
    @ToolbarContentBuilder
    private var syncStatusToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            SyncStatusIndicator(
                isSyncing: SyncCoordinator.shared.isSyncing,
                pendingCount: pendingActionsCount,
                lastSyncTime: SyncCoordinator.shared.lastSyncTime
            )
            .onTapGesture {
                showSyncDetail = true
            }
        }
    }
    
    @ToolbarContentBuilder
    private var settingsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { showingSettings = true }) {
                Image(systemName: "person.circle")
            }
            .accessibilityIdentifier("settings.button")
        }
    }
    
    @ToolbarContentBuilder
    private var actionButtonsToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                Button(action: { 
                    if checkLimit() { showingAddCustom = true }
                }) {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("inventory.addButton")
                
                Button(action: { 
                    if checkLimit() { showingScanner = true }
                }) {
                    Image(systemName: "barcode.viewfinder")
                        .fontWeight(.semibold)
                }
                .accessibilityIdentifier("inventory.scanButton")
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            configuredInventoryList
        }
    }
    
    private var configuredInventoryList: some View {
        inventoryList
            .navigationTitle("Pantry (\(viewModel.items.count))")
            .toolbar {
                syncStatusToolbarItem
                settingsToolbarItem
                actionButtonsToolbarItem
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
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                // Update pending actions count every 2 seconds
                Task { @MainActor in
                    let fetchDescriptor = FetchDescriptor<SDPendingAction>()
                    if let actions = try? modelContext.fetch(fetchDescriptor) {
                        pendingActionsCount = actions.count
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
            .overlay {
                if showSyncDetail {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showSyncDetail = false
                        }
                    
                    SyncStatusDetail(
                        isSyncing: SyncCoordinator.shared.isSyncing,
                        pendingCount: pendingActionsCount,
                        lastSyncTime: SyncCoordinator.shared.lastSyncTime,
                        isPresented: $showSyncDetail
                    ) {
                        // Manual sync
                        Task {
                            await SyncCoordinator.shared.syncNow(
                                householdId: authViewModel.currentUser?.householdId,
                                modelContext: modelContext,
                                reason: .manual
                            )
                            await viewModel.loadInventory(withLoadingState: false)
                        }
                    }
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


