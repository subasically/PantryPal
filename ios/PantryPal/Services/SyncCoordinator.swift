import Foundation
import SwiftData

/// Centralized sync coordinator with debouncing and incremental sync
@MainActor
class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()
    
    @Published var isSyncing = false
    @Published var lastSyncTime: Date?
    
    private var pendingSyncTask: Task<Void, Never>?
    private var lastSyncServerTime: [String: String] = [:] // householdId -> serverTime
    private let debounceInterval: TimeInterval = 2.5 // Debounce after-action syncs
    private let minSyncInterval: TimeInterval = 15.0 // Don't sync more than once per 15s
    
    private init() {
        loadSyncState()
    }
    
    enum SyncReason: String {
        case appActive = "App became active"
        case afterAction = "After user action"
        case pullToRefresh = "Pull to refresh"
        case householdSwitch = "Household switched"
        case bootstrap = "Initial bootstrap"
    }
    
    /// Request a sync with debouncing (for after-action)
    func requestSync(householdId: String?, modelContext: ModelContext, reason: SyncReason) {
        guard let householdId = householdId else {
            print("⏭️ [SyncCoordinator] No household, skipping sync")
            return
        }
        
        // Cancel any pending debounced sync
        pendingSyncTask?.cancel()
        
        // Check minimum interval for app-active syncs
        if reason == .appActive, let lastSync = lastSyncTime {
            let timeSinceLastSync = Date().timeIntervalSince(lastSync)
            if timeSinceLastSync < minSyncInterval {
                print("⏭️ [SyncCoordinator] Skipping \(reason.rawValue) - synced \(Int(timeSinceLastSync))s ago")
                return
            }
        }
        
        // Debounce after-action syncs
        if reason == .afterAction {
            print("⏱️ [SyncCoordinator] Debouncing \(reason.rawValue) sync...")
            pendingSyncTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
                if !Task.isCancelled {
                    await performSync(householdId: householdId, modelContext: modelContext, reason: reason)
                }
            }
        } else {
            // Immediate sync for app-active
            Task {
                await performSync(householdId: householdId, modelContext: modelContext, reason: reason)
            }
        }
    }
    
    /// Perform immediate sync (for pull-to-refresh)
    func syncNow(householdId: String?, modelContext: ModelContext, reason: SyncReason) async {
        guard let householdId = householdId else { return }
        await performSync(householdId: householdId, modelContext: modelContext, reason: reason)
    }
    
    /// Actual sync implementation
    private func performSync(householdId: String, modelContext: ModelContext, reason: SyncReason) async {
        guard !isSyncing else {
            print("⏭️ [SyncCoordinator] Sync already in progress, skipping")
            return
        }
        
        isSyncing = true
        print("🔄 [SyncCoordinator] Starting sync: \(reason.rawValue)")
        
        do {
            let lastServerTime = lastSyncServerTime[householdId]
            
            if lastServerTime == nil {
                // Bootstrap: use full sync
                print("🔄 [SyncCoordinator] No sync cursor, bootstrapping with full sync...")
                try await SyncService.shared.syncFromRemote(modelContext: modelContext)
                
                // Set initial cursor
                lastSyncServerTime[householdId] = ISO8601DateFormatter().string(from: Date())
                saveSyncState()
            } else {
                // Incremental sync
                print("🔄 [SyncCoordinator] Incremental sync since: \(lastServerTime!)")
                let serverTime = try await SyncService.shared.syncChanges(
                    since: lastServerTime!,
                    modelContext: modelContext
                )
                
                // Update cursor
                lastSyncServerTime[householdId] = serverTime
                saveSyncState()
            }
            
            lastSyncTime = Date()
            print("✅ [SyncCoordinator] Sync completed successfully")
            
        } catch {
            print("❌ [SyncCoordinator] Sync failed: \(error.userFriendlyMessage)")
        }
        
        isSyncing = false
    }
    
    /// Reset sync state for household switch
    func resetForHousehold(_ householdId: String?) {
        guard let householdId = householdId else { return }
        if lastSyncServerTime[householdId] == nil {
            print("🔄 [SyncCoordinator] New household, will bootstrap on next sync")
        }
    }
    
    // MARK: - Persistence
    
    private func loadSyncState() {
        if let data = UserDefaults.standard.data(forKey: "syncCursors"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            lastSyncServerTime = decoded
            print("📥 [SyncCoordinator] Loaded sync cursors for \(decoded.count) households")
        }
    }
    
    private func saveSyncState() {
        if let encoded = try? JSONEncoder().encode(lastSyncServerTime) {
            UserDefaults.standard.set(encoded, forKey: "syncCursors")
        }
    }
}
