import SwiftUI

struct LocationsSettingsView: View {
    @State private var locations: [LocationFlat] = []
    @State private var hierarchy: [LocationHierarchy] = []
    @State private var isLoading = true
    @State private var activeSheet: LocationSheetConfig?
    @State private var errorMessage: String?
    @State private var expandedLocations: Set<String> = []
    
    struct LocationSheetConfig: Identifiable {
        let id = UUID()
        let parentId: String?
        let parentName: String?
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if locations.isEmpty {
                emptyState
            } else {
                locationsList
            }
        }
        .navigationTitle("Storage Locations")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { 
                    activeSheet = LocationSheetConfig(parentId: nil, parentName: nil)
                }) {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $activeSheet) { config in
            AddLocationSheet(parentId: config.parentId, parentName: config.parentName, onSave: { await loadLocations() })
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            await loadLocations()
        }
    }
    
    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Locations", systemImage: "mappin.slash")
        } description: {
            Text("Set up your storage locations to organize your pantry.\n\nExample: Basement Pantry → Rack 1 → Shelf 2")
        } actions: {
            Button("Add Location") {
                activeSheet = LocationSheetConfig(parentId: nil, parentName: nil)
            }
            .buttonStyle(.ppPrimary)
        }
    }
    
    private var locationsList: some View {
        List {
            Section {
                ForEach(hierarchy, id: \.id) { location in
                    LocationTreeRow(
                        location: location,
                        level: 0,
                        expandedLocations: $expandedLocations,
                        onAddSubLocation: { id, name in
                            activeSheet = LocationSheetConfig(parentId: id, parentName: name)
                        },
                        onDelete: { id in
                            Task { await deleteLocation(id) }
                        }
                    )
                }
            } header: {
                Text("Tap + to add racks, shelves, or zones")
            } footer: {
                Text("Tip: Organize as Location → Rack → Shelf for precise tracking")
                    .font(.caption)
            }
        }
    }
    
    private func loadLocations() async {
        do {
            let hierarchyResponse = try await APIService.shared.getLocationsHierarchy()
            let flatList = try await APIService.shared.getLocations()
            locations = flatList
            hierarchy = hierarchyResponse.hierarchy
            // Auto-expand all by default
            expandedLocations = Set(flatList.filter { $0.level == 0 }.map { $0.id })
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
    
    private func deleteLocation(_ id: String) async {
        do {
            try await APIService.shared.deleteLocation(id: id)
            await loadLocations()
            HapticManager.success()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.error()
        }
    }
}

// MARK: - Location Tree Row
struct LocationTreeRow: View {
    let location: LocationHierarchy
    let level: Int
    @Binding var expandedLocations: Set<String>
    let onAddSubLocation: (String, String) -> Void
    let onDelete: (String) -> Void
    
    private var isExpanded: Bool {
        expandedLocations.contains(location.id)
    }
    
    private var hasChildren: Bool {
        !location.children.isEmpty
    }
    
    private var levelIcon: String {
        switch level {
        case 0: return "house.fill"
        case 1: return "square.grid.2x2"
        case 2: return "tray.fill"
        default: return "folder.fill"
        }
    }
    
    private var levelLabel: String {
        switch level {
        case 0: return "Location"
        case 1: return "Rack/Section"
        case 2: return "Shelf/Row"
        default: return "Sub-location"
        }
    }
    
    private var addButtonLabel: String {
        switch level {
        case 0: return "Add Rack"
        case 1: return "Add Shelf"
        default: return "Add Sub"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main row
            HStack(spacing: 12) {
                // Indentation
                if level > 0 {
                    ForEach(0..<level, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.ppPurple.opacity(0.3))
                            .frame(width: 2)
                            .padding(.vertical, 4)
                    }
                }
                
                // Expand/Collapse button
                if hasChildren {
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if isExpanded {
                                expandedLocations.remove(location.id)
                            } else {
                                expandedLocations.insert(location.id)
                            }
                        }
                    }) {
                        Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                            .foregroundColor(.ppPurple)
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: levelIcon)
                        .foregroundColor(.ppPurple.opacity(0.6))
                        .font(.system(size: 16))
                        .frame(width: 24)
                }
                
                // Location info
                VStack(alignment: .leading, spacing: 2) {
                    Text(location.name)
                        .font(level == 0 ? .headline : .subheadline)
                        .fontWeight(level == 0 ? .semibold : .medium)
                    
                    HStack(spacing: 4) {
                        Text(levelLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        if hasChildren {
                            Text("• \(location.children.count) sub-location\(location.children.count == 1 ? "" : "s")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Add sub-location button
                Button(action: {
                    onAddSubLocation(location.id, location.name)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(addButtonLabel)
                    }
                    .font(.caption)
                    .foregroundColor(.ppPurple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.ppPurple.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDelete(location.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            
            // Children (if expanded)
            if isExpanded && hasChildren {
                ForEach(location.children, id: \.id) { child in
                    LocationTreeRow(
                        location: child,
                        level: level + 1,
                        expandedLocations: $expandedLocations,
                        onAddSubLocation: onAddSubLocation,
                        onDelete: onDelete
                    )
                }
            }
        }
    }
}

struct AddLocationSheet: View {
    let parentId: String?
    let parentName: String?
    let onSave: () async -> Void
    
    @State private var name = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showQuickAdd = false
    @Environment(\.dismiss) private var dismiss
    
    private var levelHint: String {
        if parentId == nil {
            return "Main location (e.g., Basement Pantry, Kitchen Fridge)"
        } else {
            return "Sub-location under \(parentName ?? "parent")"
        }
    }
    
    private var suggestedNames: [String] {
        if parentId == nil {
            return ["Basement Pantry", "Kitchen Cabinet", "Garage Shelf", "Chest Freezer", "Kitchen Fridge"]
        } else {
            return ["Rack 1", "Rack 2", "Shelf 1", "Shelf 2", "Shelf 3", "Top Shelf", "Middle Shelf", "Bottom Shelf", "Left Side", "Right Side"]
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Location Name", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    if let parentName = parentName {
                        HStack {
                            Image(systemName: "arrow.turn.down.right")
                            Text("Adding under: \(parentName)")
                        }
                    } else {
                        Text("Add Main Location")
                    }
                } footer: {
                    Text(levelHint)
                }
                
                Section("Quick Add") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                        ForEach(suggestedNames, id: \.self) { suggestion in
                            Button(action: {
                                name = suggestion
                            }) {
                                Text(suggestion)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(name == suggestion ? Color.ppPurple : Color.ppPurple.opacity(0.1))
                                    .foregroundColor(name == suggestion ? .white : .ppPurple)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle(parentId != nil ? "Add Sub-location" : "Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task { await saveLocation() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    private func saveLocation() async {
        isLoading = true
        
        do {
            _ = try await APIService.shared.createLocation(name: name.trimmingCharacters(in: .whitespaces), parentId: parentId)
            HapticManager.success()
            await onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            HapticManager.error()
        }
        
        isLoading = false
    }
}

// Location picker for use in forms
struct LocationPicker: View {
    @Binding var selectedLocationId: String?
    let locations: [LocationFlat]
    
    var body: some View {
        Picker("Location", selection: $selectedLocationId) {
            Text("Select Location").tag(nil as String?)
            ForEach(locations) { location in
                Text(location.fullPath)
                    .tag(location.id as String?)
            }
        }
    }
}

#Preview {
    NavigationStack {
        LocationsSettingsView()
    }
}
