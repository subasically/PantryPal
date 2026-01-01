# iOS SwiftUI Architecture & Development

Expert guidance for implementing PantryPal iOS features with SwiftUI and SwiftData.

## When to Use
- Adding new iOS features
- Fixing UI bugs
- Implementing ViewModels
- Working with SwiftData
- Questions about iOS architecture

## Tech Stack
- **Language:** Swift 6 (Strict Concurrency)
- **UI:** SwiftUI (iOS 18+)
- **Architecture:** MVVM (@Observable ViewModels)
- **Storage:** SwiftData (offline-first caching)
- **Auth:** JWT + Apple Sign In
- **API:** URLSession (async/await)

## Quick Reference

### Project Structure
```
ios/PantryPal/
├── PantryPalApp.swift           # App entry + ModelContainer
├── Models/
│   ├── Models.swift             # API models (Codable)
│   └── SwiftDataModels.swift    # @Model classes (SD prefix)
├── Views/
│   ├── InventoryListView.swift
│   ├── GroceryListView.swift
│   └── LoginView.swift
├── ViewModels/
│   ├── AuthViewModel.swift      # @Observable
│   └── InventoryViewModel.swift # @Observable
├── Services/
│   ├── APIService.swift         # REST client
│   └── SyncService.swift        # Offline sync
└── Utils/
    ├── AppError.swift           # Error types
    └── AccessibilityIdentifiers.swift
```

### ViewModel Pattern (@Observable)
```swift
import SwiftUI
import SwiftData

@MainActor
@Observable
final class InventoryViewModel {
    var items: [InventoryItem] = []
    var isLoading = false
    var errorMessage: String?
    
    private var modelContext: ModelContext?
    
    func setContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    func loadInventory() async {
        isLoading = true
        defer { isLoading = false }
        
        // Load from SwiftData cache
        guard let context = modelContext else { return }
        let descriptor = FetchDescriptor<SDInventoryItem>()
        items = try? context.fetch(descriptor).map { $0.toDomain() }
        
        // Sync with server
        await SyncService.shared.syncInventory()
    }
}
```

### View Pattern
```swift
struct InventoryListView: View {
    @Environment(AuthViewModel.self) private var authViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = InventoryViewModel()
    
    var body: some View {
        NavigationStack {
            List(viewModel.items) { item in
                Text(item.name)
            }
            .navigationTitle("Pantry")
            .task {
                viewModel.setContext(modelContext)
                await viewModel.loadInventory()
            }
        }
    }
}
```

### SwiftData Model Pattern
```swift
import SwiftData

@Model
final class SDInventoryItem {
    @Attribute(.unique) var id: String
    var householdId: String
    var quantity: Int
    var productId: String
    
    @Relationship var product: SDProduct?
    
    init(id: String, householdId: String, quantity: Int, productId: String) {
        self.id = id
        self.householdId = householdId
        self.quantity = quantity
        self.productId = productId
    }
    
    func toDomain() -> InventoryItem {
        InventoryItem(id: id, quantity: quantity, ...)
    }
}
```

### API Service Pattern
```swift
// APIError is FILE-LEVEL (not nested in APIService)
enum APIError: Error {
    case unauthorized
    case serverError(String)
}

@MainActor
final class APIService {
    static let shared = APIService()
    
    func login(email: String, password: String) async throws -> AuthResponse {
        try await request(endpoint: "/auth/login", method: "POST", ...)
    }
    
    private func request<T: Decodable>(...) async throws -> T {
        // URLSession + JWT auth
    }
}
```

### Error Handling
```swift
do {
    try await viewModel.addItem(...)
    ToastCenter.shared.show("Item added!", type: .success)
} catch {
    ToastCenter.shared.show(error.userFriendlyMessage, type: .error)
}
```

### Accessibility Identifiers
```swift
// ✅ Use string literals directly
Button("Add Item") { }
    .accessibilityIdentifier("inventory.addButton")

TextField("Name", text: $name)
    .accessibilityIdentifier("addItem.nameField")

// Pattern: <screen>.<elementType><OptionalName>
```

## Implementation Checklist

When adding new feature:
- [ ] Identify affected Views, ViewModels, Models
- [ ] Check existing patterns in similar features
- [ ] Create SwiftData models with SD prefix
- [ ] Implement ViewModel with @Observable
- [ ] Create SwiftUI View with accessibility IDs
- [ ] Add error handling with AppError
- [ ] Check premium limits if adding data
- [ ] Test with offline mode
- [ ] Verify sync works correctly

## Critical Patterns

### State Management
```swift
// ✅ Use @State for local view state
@State private var showingSheet = false

// ✅ Use @Environment for shared ViewModels
@Environment(AuthViewModel.self) private var authViewModel

// ✅ Use @Environment(\.modelContext) for SwiftData
@Environment(\.modelContext) private var modelContext
```

### Async Operations
```swift
// ✅ Use .task for lifecycle async work
.task {
    await viewModel.load()
}

// ✅ Use Task for button actions
Button("Save") {
    Task {
        await viewModel.save()
    }
}
```

### Loading States (Minimum 1.5s)
```swift
func save() async {
    let startTime = Date()
    defer {
        let elapsed = Date().timeIntervalSince(startTime)
        if elapsed < 1.5 {
            try? await Task.sleep(nanoseconds: UInt64((1.5 - elapsed) * 1_000_000_000))
        }
    }
    
    // Save logic
}
```

### Premium Checks
```swift
func checkLimit() -> Bool {
    let isPremium = authViewModel.currentHousehold?.isPremiumActive ?? false
    let count = viewModel.items.count
    
    if !isPremium && count >= 25 {
        showingPaywall = true
        return false
    }
    return true
}
```

## Common Gotchas

### ❌ Missing SwiftData Import
```swift
// ERROR: Cannot find type 'FetchDescriptor' in scope
let descriptor = FetchDescriptor<SDInventoryItem>()

// FIX: Add import
import SwiftData
```

### ❌ Wrong APIError Usage
```swift
// WRONG: APIError is NOT nested
throw APIService.APIError.unauthorized

// CORRECT: It's file-level
throw APIError.unauthorized
```

### ❌ Wrong Property Names
```swift
// WRONG
authViewModel.user
authViewModel.householdInfo

// CORRECT
authViewModel.currentUser
authViewModel.currentHousehold
```

### ✅ Always Check SwiftData Import
Files using these need `import SwiftData`:
- `@Query` property wrapper
- `FetchDescriptor`
- `modelContext.fetch()`
- `@Model` macro

## Key Files
- **Auth:** `LoginView.swift`, `AuthViewModel.swift`
- **Inventory:** `InventoryListView.swift`, `InventoryViewModel.swift`
- **Grocery:** `GroceryListView.swift`, `GroceryViewModel.swift`
- **Models:** `Models.swift` (API), `SwiftDataModels.swift` (cache)
- **Services:** `APIService.swift`, `SyncService.swift`
- **Errors:** `AppError.swift`, `AppErrorMapper.swift`
