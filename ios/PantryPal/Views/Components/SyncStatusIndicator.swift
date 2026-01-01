import SwiftUI

/// Sync status indicator showing current sync state and pending actions
struct SyncStatusIndicator: View {
    let isSyncing: Bool
    let pendingCount: Int
    let lastSyncTime: Date?
    
    @State private var isExpanded = false
    
    var body: some View {
        HStack(spacing: 8) {
            if isSyncing {
                // Syncing state
                ProgressView()
                    .scaleEffect(0.8)
                Text("Syncing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if pendingCount > 0 {
                // Pending actions (offline)
                Image(systemName: "arrow.clockwise.circle.fill")
                    .foregroundStyle(.orange)
                Text("\(pendingCount) pending")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let lastSync = lastSyncTime {
                // Synced successfully
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Synced \(timeAgo(lastSync))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Never synced
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.gray)
                Text("Not synced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .onTapGesture {
            withAnimation(.snappy) {
                isExpanded.toggle()
            }
        }
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours)h ago"
        } else {
            let days = seconds / 86400
            return "\(days)d ago"
        }
    }
}

/// Expanded sync status view with detailed information
struct SyncStatusDetail: View {
    let isSyncing: Bool
    let pendingCount: Int
    let lastSyncTime: Date?
    @Binding var isPresented: Bool
    let onManualSync: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Text("Sync Status")
                    .font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .imageScale(.large)
                }
            }
            
            Divider()
            
            // Status rows
            VStack(alignment: .leading, spacing: 12) {
                // Current status
                HStack {
                    Label(isSyncing ? "Syncing" : "Status", systemImage: isSyncing ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                        .foregroundStyle(isSyncing ? .blue : .green)
                    Spacer()
                    if !isSyncing {
                        Text("Up to date")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Last sync
                if let lastSync = lastSyncTime {
                    HStack {
                        Label("Last Sync", systemImage: "clock")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(lastSync, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Pending actions
                HStack {
                    Label("Pending Changes", systemImage: "tray.fill")
                        .foregroundStyle(pendingCount > 0 ? .orange : .secondary)
                    Spacer()
                    Text("\(pendingCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Divider()
            
            // Manual sync button
            Button {
                onManualSync()
                isPresented = false
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Sync Now")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(isSyncing)
            
            // Info text
            Text("Changes are automatically synced when online. Tap 'Sync Now' to force an immediate sync.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: 400)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(radius: 10)
    }
}

#Preview {
    VStack(spacing: 20) {
        SyncStatusIndicator(isSyncing: true, pendingCount: 0, lastSyncTime: nil)
        SyncStatusIndicator(isSyncing: false, pendingCount: 3, lastSyncTime: nil)
        SyncStatusIndicator(isSyncing: false, pendingCount: 0, lastSyncTime: Date().addingTimeInterval(-120))
        SyncStatusIndicator(isSyncing: false, pendingCount: 0, lastSyncTime: nil)
    }
    .padding()
}
