# Barcode Scanner Flow Analysis

**Date:** 2025-12-29  
**Component:** Barcode Scanner → Inventory Database

---

## 📱 Overview

PantryPal has **two scanning modes**:
1. **Smart Scanner** (New, AI-powered) - Multi-step with OCR
2. **Classic Scanner** (Legacy) - Quick UPC lookup

User preference: `UserPreferences.shared.useSmartScanner`

---

## 🔄 Flow Diagram

```
User Taps Scan Button
         ↓
   Check Item Limit (Free: 30, Premium: ∞)
         ↓
   [Limit OK?] → NO → Show Paywall
         ↓ YES
   Show Scanner (Smart or Classic)
         ↓
   AVFoundation Captures Barcode
         ↓
   [Which Scanner Mode?]
         ↓
   ┌─────────────┴─────────────┐
   ↓                           ↓
SMART SCANNER             CLASSIC SCANNER
(Multi-step)              (Single-step)
```

---

## 🎯 SMART SCANNER FLOW

**File:** `SmartScannerView.swift`

### Step 1: Scan Barcode
```swift
BarcodeScannerView → captures UPC
         ↓
APIService.shared.lookupUPC(code)
         ↓
[Product Found?]
   YES → currentStep = .expirationPhoto
   NO  → currentStep = .productPhoto
```

### Step 2: Product Photo (if unknown product)
- User takes photo of product
- OCR extracts product name (future feature)
- Currently: User enters name manually

### Step 3: Expiration Photo
- User takes photo of expiration date
- OCR extracts date (future feature)
- Currently: Skip or enter manually

### Step 4: Review
```swift
onItemScanned?(name, upc, date)
         ↓
viewModel.addSmartItem(name: name, upc: upc, expirationDate: date)
         ↓
1. Create/Find Product Locally (SwiftData)
2. Enqueue Product Creation (ActionQueue)
3. Add Inventory Item
```

**Key Code:**
```swift
// SmartScannerView.swift:106-114
SmartScannerView(isPresented: $showingScanner, onItemScanned: { name, upc, date in
    Task {
        let success = await viewModel.addSmartItem(name: name, upc: upc, expirationDate: date)
        if success {
            showSuccessToast("Added \(name) to pantry!")
        }
    }
})
```

---

## ⚡ CLASSIC SCANNER FLOW (Quick Add)

**File:** `InventoryListView.swift:119-124`

### Single-Step Process
```swift
ScannerSheet → captures UPC
         ↓
viewModel.quickAdd(upc, quantity, expirationDate, locationId)
         ↓
APIService.shared.quickAdd(...)
         ↓
Server: /api/inventory/quick-add
```

### Server-Side (quick-add)

**File:** `server/src/routes/inventory.js` (~line 233)

```javascript
POST /api/inventory/quick-add
1. Check write permission (Premium household check)
2. Check inventory limit (FREE_LIMIT = 30)
3. Verify location exists
4. Find or create product:
   a. Check local DB for UPC
   b. If not found → External API lookup (Open Food Facts)
   c. If still not found → Require custom product creation
5. Find or update existing inventory item:
   a. Check if item already exists (same product + household)
   b. If exists → Increment quantity
   c. If new → Create new inventory item
6. Return item + product data
```

**Response Structure:**
```json
{
  "item": {
    "id": "uuid",
    "product_id": "uuid",
    "household_id": "uuid",
    "quantity": 1,
    "expiration_date": "2025-12-30",
    "location_id": "uuid",
    "product_name": "Coca-Cola",
    "product_brand": "Coca-Cola Company",
    "product_upc": "049000050103",
    "product_image_url": "https://...",
    "product_category": "Beverages"
  },
  "requiresCustomProduct": false
}
```

---

## 💾 Local Database Update (iOS)

**File:** `InventoryViewModel.swift:246-335`

### After Successful API Call:

```swift
1. Ensure Product Exists in SwiftData
   - FetchDescriptor<SDProduct> by ID
   - If not found → Insert new SDProduct
   
2. Update/Insert Inventory Item
   - FetchDescriptor<SDInventoryItem> by ID
   - If exists → Update quantity, expiration, location
   - If new → Insert new SDInventoryItem
   
3. Save Context
   - try? context.save()
   
4. Refresh UI
   - items array automatically updates (via @Query or manual fetch)
```

**Key Code:**
```swift
// InventoryViewModel.swift:262-278
let newProd = SDProduct(
    id: productId,
    upc: item.productUpc,
    name: item.productName ?? "Unknown",
    brand: item.productBrand,
    details: nil,
    imageUrl: item.productImageUrl,
    category: item.productCategory,
    isCustom: false,
    householdId: item.householdId
)
context.insert(newProd)
```

---

## 🔍 Barcode Scanner Implementation

**File:** `BarcodeScannerView.swift`

### AVFoundation Setup:

```swift
class BarcodeScannerViewController: UIViewController {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    func setupCaptureSession() {
        1. Create AVCaptureSession
        2. Get back camera device
        3. Create device input
        4. Add metadata output (EAN13, UPC-E, Code128, etc.)
        5. Set delegate to receive scanned codes
        6. Create preview layer
        7. Start session
    }
}
```

### Supported Barcode Types:
- `.ean8`
- `.ean13`
- `.upce`
- `.code128`
- `.code39`
- `.code93`
- `.qr`

### Scan Detection:
```swift
extension BarcodeScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(..., didOutput metadataObjects: [AVMetadataObject], ...) {
        guard let code = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let stringValue = code.stringValue else { return }
        
        // Prevent duplicate scans
        if !hasScanned {
            hasScanned = true
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onCodeFound?(stringValue)
        }
    }
}
```

---

## 🎨 UI Features

### Visual Feedback:
- **Scan Overlay:** Semi-transparent black with cutout frame
- **Border:** White rounded rectangle (280x140)
- **Instruction Label:** "Align barcode within frame"
- **Haptic Feedback:** Vibration on successful scan
- **Sound:** Optional beep (barcode-beep.mp3)

### User Experience:
1. Scanner opens full-screen
2. User aligns barcode within frame
3. Camera auto-focuses and detects barcode
4. Vibrates + pauses scanning
5. Shows result or proceeds to next step

---

## 🔐 Permission & Limit Checks

### Before Scanning:

**File:** `InventoryListView.swift`

```swift
func checkLimit() -> Bool {
    // Check if Premium
    if authViewModel.currentHousehold?.isPremium == true {
        return true
    }
    
    // Check free limit
    if viewModel.items.count >= authViewModel.freeLimit {
        showingPaywall = true
        return false
    }
    
    return true
}
```

### On Server:

```javascript
// Check write permission (Premium household)
function checkWritePermission(householdId) {
    if (!householdId) return true; // Single user
    const household = db.prepare('SELECT id FROM households WHERE id = ?').get(householdId);
    return !household; // If household exists, need Premium
}

// Check item limit
function checkInventoryLimit(householdId) {
    const count = db.prepare('SELECT COUNT(*) as count FROM inventory WHERE household_id = ?').get(householdId).count;
    return count < FREE_LIMIT; // 30 items
}
```

---

## 📊 Database Schema

### Products Table:
```sql
CREATE TABLE products (
    id TEXT PRIMARY KEY,
    upc TEXT,
    name TEXT NOT NULL,
    brand TEXT,
    description TEXT,
    image_url TEXT,
    category TEXT,
    is_custom BOOLEAN DEFAULT 0,
    household_id TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
```

### Inventory Table:
```sql
CREATE TABLE inventory (
    id TEXT PRIMARY KEY,
    product_id TEXT NOT NULL,
    household_id TEXT NOT NULL,
    quantity INTEGER DEFAULT 1,
    expiration_date TEXT,
    location_id TEXT,
    notes TEXT,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id),
    FOREIGN KEY (household_id) REFERENCES households(id),
    FOREIGN KEY (location_id) REFERENCES locations(id)
);
```

---

## 🚀 Performance Optimizations

### 1. Optimistic UI Updates
- Insert to SwiftData immediately
- Show item in list before server confirms
- If server fails → ActionQueue retries

### 2. Offline Support
- ActionQueueService queues failed requests
- Syncs when back online
- User sees item immediately

### 3. Local Caching
- SwiftData stores all products & items
- First load from cache (instant)
- Background sync from server

### 4. Duplicate Prevention
- Server checks: same product + household
- Increments quantity instead of creating duplicate
- Returns existing item if found

---

## ⚠️ Error Handling

### iOS Errors:
1. **Camera Permission Denied** → Show settings alert
2. **No Location** → "Please create a location first"
3. **Limit Reached** → Show paywall
4. **Network Error** → Queue action, show optimistic UI
5. **Product Not Found** → Require custom product creation

### Server Errors:
1. **403 PREMIUM_REQUIRED** → Need Premium for household sharing
2. **403 LIMIT_REACHED** → Free tier limit (30 items)
3. **404 Location Not Found** → Invalid locationId
4. **400 UPC Required** → Missing barcode
5. **500 External API Failed** → UPC lookup service down

---

## 🔄 Sync Flow

### Initial Load:
```
App Launch
    ↓
SyncService.syncFromRemote()
    ↓
Fetch /api/sync/full
    ↓
Update SwiftData (Products, Locations, Inventory)
    ↓
UI Updates Automatically (@Query)
```

### After Scan:
```
Scan → Quick Add → Server Success
    ↓
Update SwiftData
    ↓
UI Shows New Item
    ↓
Background Sync (Pull to Refresh)
```

---

## 📝 Key Files Reference

### iOS:
- **Scanner:** `BarcodeScannerView.swift`
- **Smart Scanner:** `SmartScannerView.swift`
- **Inventory List:** `InventoryListView.swift`
- **View Model:** `InventoryViewModel.swift`
- **API Service:** `APIService.swift`
- **Sync Service:** `SyncService.swift`
- **Action Queue:** `ActionQueueService.swift`

### Server:
- **Quick Add:** `server/src/routes/inventory.js` (POST /quick-add)
- **UPC Lookup:** `server/src/services/upcLookup.js`
- **Auth Middleware:** `server/src/middleware/auth.js`
- **Database:** `server/src/models/database.js`

---

## 🎯 User Journey Example

**Scenario:** User scans a Coca-Cola bottle

1. **User:** Taps scan button in Pantry tab
2. **App:** Checks if under 30 items (Free tier)
3. **App:** Opens camera with BarcodeScannerView
4. **User:** Points camera at barcode
5. **AVFoundation:** Detects barcode "049000050103"
6. **App:** Vibrates, calls quickAdd()
7. **API Request:** POST /api/inventory/quick-add
8. **Server:** Looks up UPC in products table
9. **Server:** Not found → Queries Open Food Facts API
10. **Open Food Facts:** Returns product data
11. **Server:** Creates product in database
12. **Server:** Creates inventory item (qty=1)
13. **Server:** Returns item + product data
14. **App:** Updates SwiftData
15. **UI:** Shows "Added Coca-Cola to pantry!" 🎉
16. **User:** Sees item appear in list

Total time: **~2 seconds** 🚀

---

## 🔮 Future Improvements

### Planned:
- [ ] OCR for expiration dates (SmartScanner)
- [ ] OCR for product names from photos
- [ ] Batch scanning (scan multiple items)
- [ ] Barcode scan history
- [ ] Custom barcode generation for unlabeled items

### Considerations:
- Use Vision framework for OCR
- Add confidence scores for OCR results
- Allow user to correct OCR mistakes
- Store scan history for analytics

---

**Last Updated:** 2025-12-29  
**Version:** v1.0 (Current MVP)
