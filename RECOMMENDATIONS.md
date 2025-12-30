# Recommendations for Reducing Regression Bugs

**Date:** December 30, 2024  
**Context:** Based on recent bugs found (location validation, grocery auto-add, Premium permission check)  
**Goal:** Make codebase easier to maintain and reduce regression bugs

---

## 📊 Issues Found & Patterns

### Issue 1: Broken `checkWritePermission()` Function
- **File:** `server/src/routes/grocery.js`
- **Problem:** Logic was inverted (`return !household`), blocking everyone
- **Pattern:** Helper function logic error with no validation

### Issue 2: Bypassed Grocery Logic in UI
- **File:** `ios/PantryPal/Views/InventoryListView.swift`
- **Problem:** [-] button directly called `adjustQuantity`, skipping grocery handler
- **Pattern:** Multiple code paths doing same thing differently

### Issue 3: Missing Location Validation
- **File:** Both server and iOS
- **Problem:** No validation that location was required/valid
- **Pattern:** Defensive validation missing at both layers

### Issue 4: Duplicate `checkWritePermission()` Functions
- **Files:** `grocery.js`, `inventory.js`, `checkout.js` (3 copies!)
- **Problem:** Same logic duplicated, can get out of sync
- **Pattern:** No shared utilities module

---

## 🎯 Core Recommendations

### 1. **Centralize Business Logic (Server)**

#### Problem:
- `checkWritePermission()` duplicated in 3 files
- `isHouseholdPremium()` helper exists in some files but not used consistently
- Permission logic scattered across routes

#### Solution: Create Shared Services/Utils

**Create:** `server/src/services/premiumService.js`

```javascript
const db = require('../models/database');

/**
 * Check if household has active Premium subscription
 * @param {string} householdId 
 * @returns {boolean}
 */
function isHouseholdPremium(householdId) {
    if (!householdId) return false;
    
    const household = db.prepare(`
        SELECT is_premium, premium_expires_at 
        FROM households 
        WHERE id = ?
    `).get(householdId);
    
    if (!household || !household.is_premium) return false;
    
    // Check expiration
    if (household.premium_expires_at) {
        const expiresAt = new Date(household.premium_expires_at);
        if (expiresAt <= new Date()) {
            console.log(`[Premium] Household ${householdId} Premium expired at ${expiresAt}`);
            return false;
        }
    }
    
    return true;
}

/**
 * Check if user can write to household resources
 * Single-member households: always allowed
 * Multi-member households: requires Premium
 * 
 * @param {string} householdId 
 * @returns {boolean}
 */
function canWriteToHousehold(householdId) {
    if (!householdId) return true; // No household = single user
    
    const result = db.prepare(`
        SELECT 
            h.id,
            h.is_premium,
            h.premium_expires_at,
            (SELECT COUNT(*) FROM users WHERE household_id = h.id) as member_count
        FROM households h
        WHERE h.id = ?
    `).get(householdId);
    
    if (!result) {
        console.warn(`[Permission] Household ${householdId} not found`);
        return true; // Shouldn't happen, but allow
    }
    
    // Single-member household: always allow
    if (result.member_count <= 1) {
        console.log(`[Permission] Single-member household ${householdId}: ALLOW`);
        return true;
    }
    
    // Multi-member: require Premium
    const isPremium = isHouseholdPremium(householdId);
    console.log(`[Permission] Multi-member household ${householdId} (${result.member_count} members): ${isPremium ? 'ALLOW' : 'DENY'}`);
    return isPremium;
}

/**
 * Check if household is under the free tier limit for a resource
 * @param {string} householdId 
 * @param {string} resourceType - 'inventory' or 'grocery'
 * @param {number} freeLimit - Default 25
 * @returns {boolean}
 */
function isUnderLimit(householdId, resourceType, freeLimit = 25) {
    if (!householdId) return true;
    if (isHouseholdPremium(householdId)) return true; // Premium = unlimited
    
    const table = resourceType === 'inventory' ? 'inventory' : 'grocery_items';
    const count = db.prepare(`
        SELECT COUNT(*) as count 
        FROM ${table} 
        WHERE household_id = ?
    `).get(householdId).count;
    
    const underLimit = count < freeLimit;
    console.log(`[Limit] ${resourceType} for ${householdId}: ${count}/${freeLimit} ${underLimit ? 'UNDER' : 'OVER'}`);
    return underLimit;
}

module.exports = {
    isHouseholdPremium,
    canWriteToHousehold,
    isUnderLimit
};
```

**Then in routes:**
```javascript
const { canWriteToHousehold, isUnderLimit } = require('../services/premiumService');

router.post('/', authenticateToken, (req, res) => {
    if (!canWriteToHousehold(req.user.householdId)) {
        return res.status(403).json({
            error: 'Household sharing is a Premium feature.',
            code: 'PREMIUM_REQUIRED'
        });
    }
    
    if (!isUnderLimit(req.user.householdId, 'grocery')) {
        return res.status(403).json({
            error: 'Free tier limit reached (25 items).',
            code: 'LIMIT_REACHED'
        });
    }
    
    // ... rest of logic
});
```

**Benefits:**
- ✅ Single source of truth for Premium logic
- ✅ Consistent logging across all routes
- ✅ Easy to test (one function to unit test)
- ✅ Easy to update (change in one place)

---

### 2. **Validation Layer (Server)**

#### Problem:
- Location validation added reactively after bug found
- No consistent pattern for required fields
- Validation logic mixed with business logic

#### Solution: Create Validation Middleware

**Create:** `server/src/middleware/validation.js`

```javascript
/**
 * Validation middleware factory
 * Usage: router.post('/', validate.inventory.create, handler)
 */

const db = require('../models/database');

function validateInventoryCreate(req, res, next) {
    const { productId, quantity, locationId } = req.body;
    const householdId = req.user.householdId;
    
    // Required fields
    if (!productId) {
        return res.status(400).json({ 
            error: 'Product ID is required',
            code: 'VALIDATION_ERROR',
            field: 'productId'
        });
    }
    
    if (!locationId) {
        return res.status(400).json({ 
            error: 'Location is required for inventory items',
            code: 'LOCATION_REQUIRED',
            field: 'locationId'
        });
    }
    
    if (!quantity || quantity < 1) {
        return res.status(400).json({ 
            error: 'Quantity must be at least 1',
            code: 'VALIDATION_ERROR',
            field: 'quantity'
        });
    }
    
    // Validate location exists and belongs to household
    const location = db.prepare(`
        SELECT id FROM locations 
        WHERE id = ? AND household_id = ?
    `).get(locationId, householdId);
    
    if (!location) {
        return res.status(400).json({ 
            error: 'Invalid location or location does not belong to this household',
            code: 'INVALID_LOCATION',
            field: 'locationId'
        });
    }
    
    next();
}

function validateInventoryUpdate(req, res, next) {
    const { locationId } = req.body;
    const householdId = req.user.householdId;
    
    // If location is being updated, validate it
    if (locationId !== undefined) {
        if (!locationId) {
            return res.status(400).json({ 
                error: 'Location cannot be empty',
                code: 'LOCATION_REQUIRED',
                field: 'locationId'
            });
        }
        
        const location = db.prepare(`
            SELECT id FROM locations 
            WHERE id = ? AND household_id = ?
        `).get(locationId, householdId);
        
        if (!location) {
            return res.status(400).json({ 
                error: 'Invalid location',
                code: 'INVALID_LOCATION',
                field: 'locationId'
            });
        }
    }
    
    next();
}

function validateGroceryCreate(req, res, next) {
    const { name } = req.body;
    
    if (!name || !name.trim()) {
        return res.status(400).json({ 
            error: 'Item name is required',
            code: 'VALIDATION_ERROR',
            field: 'name'
        });
    }
    
    next();
}

module.exports = {
    inventory: {
        create: validateInventoryCreate,
        update: validateInventoryUpdate
    },
    grocery: {
        create: validateGroceryCreate
    }
};
```

**Usage:**
```javascript
const validate = require('../middleware/validation');

router.post('/inventory', validate.inventory.create, (req, res) => {
    // All validation already passed, just handle business logic
});

router.put('/inventory/:id', validate.inventory.update, (req, res) => {
    // Location already validated if provided
});
```

**Benefits:**
- ✅ Validation separate from business logic
- ✅ Consistent error responses
- ✅ Easy to add new validations
- ✅ Self-documenting (see all required fields in one place)

---

### 3. **Shared UI Handlers (iOS)**

#### Problem:
- Grocery logic duplicated in `InventoryListView` and `CheckoutView`
- [-] button vs delete confirmation had different code paths
- Hard to ensure consistent behavior

#### Solution: Create Shared Service

**Create:** `ios/PantryPal/Services/GroceryService.swift`

```swift
import Foundation

@MainActor
final class GroceryService {
    static let shared = GroceryService()
    
    private init() {}
    
    /// Handle item hitting zero quantity
    /// - Parameters:
    ///   - itemName: Display name of item
    ///   - isPremium: Whether household is Premium
    ///   - onSuccess: Callback for successful add (show toast)
    ///   - onPrompt: Callback for Free user (show alert)
    func handleItemHitZero(
        itemName: String,
        isPremium: Bool,
        onSuccess: @escaping (String) -> Void,
        onPrompt: @escaping (String) -> Void
    ) async {
        print("🛒 [GroceryService] handleItemHitZero")
        print("🛒 [GroceryService] - itemName: \(itemName)")
        print("🛒 [GroceryService] - isPremium: \(isPremium)")
        
        if isPremium {
            // Premium: Auto-add
            await autoAddToGrocery(itemName: itemName, onSuccess: onSuccess)
        } else {
            // Free: Prompt
            print("🛒 [GroceryService] Free user - triggering prompt callback")
            onPrompt(itemName)
        }
    }
    
    private func autoAddToGrocery(
        itemName: String,
        onSuccess: @escaping (String) -> Void
    ) async {
        print("🛒 [GroceryService] Attempting auto-add for: \(itemName)")
        
        do {
            _ = try await APIService.shared.addGroceryItem(name: itemName)
            print("🛒 [GroceryService] ✅ Successfully auto-added")
            onSuccess(itemName)
            HapticService.shared.success()
        } catch {
            // Silently fail for Premium (don't interrupt UX)
            print("🛒 [GroceryService] ❌ Failed to auto-add: \(error)")
        }
    }
    
    /// Manually add to grocery with feedback
    func manualAddToGrocery(itemName: String) async throws {
        print("🛒 [GroceryService] Manual add: \(itemName)")
        _ = try await APIService.shared.addGroceryItem(name: itemName)
        print("🛒 [GroceryService] ✅ Manual add successful")
    }
}
```

**Usage in Views:**

```swift
// InventoryListView.swift
private func handleItemRemoval(item: InventoryItem) async {
    let isPremium = authViewModel.currentHousehold?.isPremiumActive ?? false
    let itemName = item.displayName
    let wasLastItem = item.quantity == 1
    
    await viewModel.adjustQuantity(id: item.id, adjustment: -1)
    
    if wasLastItem {
        await GroceryService.shared.handleItemHitZero(
            itemName: itemName,
            isPremium: isPremium,
            onSuccess: { name in
                self.toastMessage = "Out of \(name) — added to Grocery List"
                self.toastType = .success
                self.showToast = true
            },
            onPrompt: { name in
                self.pendingGroceryItem = name
                self.showGroceryPrompt = true
            }
        )
    }
}
```

**Benefits:**
- ✅ Single source of truth for grocery logic
- ✅ Consistent behavior across all views
- ✅ Easy to test (mock the service)
- ✅ Centralized logging

---

### 4. **Type Safety for Error Codes (Both)**

#### Problem:
- Error codes are strings ("PREMIUM_REQUIRED", "LIMIT_REACHED")
- Easy to mistype, no autocomplete
- Client and server can get out of sync

#### Solution: Shared Error Code Constants

**Server:** `server/src/constants/errors.js`

```javascript
const ErrorCodes = {
    // Auth
    UNAUTHORIZED: 'UNAUTHORIZED',
    TOKEN_EXPIRED: 'TOKEN_EXPIRED',
    
    // Premium
    PREMIUM_REQUIRED: 'PREMIUM_REQUIRED',
    LIMIT_REACHED: 'LIMIT_REACHED',
    
    // Validation
    VALIDATION_ERROR: 'VALIDATION_ERROR',
    LOCATION_REQUIRED: 'LOCATION_REQUIRED',
    INVALID_LOCATION: 'INVALID_LOCATION',
    
    // Resources
    NOT_FOUND: 'NOT_FOUND',
    ALREADY_EXISTS: 'ALREADY_EXISTS'
};

module.exports = ErrorCodes;
```

**Usage:**
```javascript
const ErrorCodes = require('../constants/errors');

return res.status(403).json({
    error: 'Premium required',
    code: ErrorCodes.PREMIUM_REQUIRED  // Autocomplete!
});
```

**iOS:** `ios/PantryPal/Models/ErrorCodes.swift`

```swift
enum ServerErrorCode: String, Codable {
    // Auth
    case unauthorized = "UNAUTHORIZED"
    case tokenExpired = "TOKEN_EXPIRED"
    
    // Premium
    case premiumRequired = "PREMIUM_REQUIRED"
    case limitReached = "LIMIT_REACHED"
    
    // Validation
    case validationError = "VALIDATION_ERROR"
    case locationRequired = "LOCATION_REQUIRED"
    case invalidLocation = "INVALID_LOCATION"
    
    // Resources
    case notFound = "NOT_FOUND"
    case alreadyExists = "ALREADY_EXISTS"
}

struct ServerErrorResponse: Codable {
    let error: String
    let code: ServerErrorCode
    let field: String?
    let upgradeRequired: Bool?
}
```

**Usage:**
```swift
if let errorResponse = try? JSONDecoder().decode(ServerErrorResponse.self, from: data) {
    switch errorResponse.code {
    case .premiumRequired:
        NotificationCenter.default.post(name: .showPaywall, object: nil)
    case .limitReached:
        // Show limit reached message
    case .locationRequired:
        // Highlight location field
    default:
        // Generic error
    }
}
```

**Benefits:**
- ✅ Type safety (compiler catches typos)
- ✅ Autocomplete in IDE
- ✅ Easy to see all error codes in one place
- ✅ Client and server stay in sync

---

### 5. **Consistent Logging Pattern**

#### Problem:
- Some logs use emojis, some don't
- No consistent format
- Hard to filter/search logs

#### Solution: Structured Logging

**Server:** Use a logging utility

```javascript
// server/src/utils/logger.js
const LOG_LEVELS = {
    DEBUG: 'DEBUG',
    INFO: 'INFO',
    WARN: 'WARN',
    ERROR: 'ERROR'
};

function log(level, category, message, data = {}) {
    const timestamp = new Date().toISOString();
    const dataStr = Object.keys(data).length > 0 
        ? JSON.stringify(data) 
        : '';
    
    console.log(`[${timestamp}] [${level}] [${category}] ${message} ${dataStr}`);
}

module.exports = {
    debug: (category, message, data) => log(LOG_LEVELS.DEBUG, category, message, data),
    info: (category, message, data) => log(LOG_LEVELS.INFO, category, message, data),
    warn: (category, message, data) => log(LOG_LEVELS.WARN, category, message, data),
    error: (category, message, data) => log(LOG_LEVELS.ERROR, category, message, data)
};
```

**Usage:**
```javascript
const logger = require('../utils/logger');

logger.info('Premium', 'Checking household status', { 
    householdId, 
    memberCount: 2, 
    isPremium: true 
});

logger.warn('Limit', 'Approaching free tier limit', { 
    householdId, 
    currentCount: 24,
    limit: 25 
});
```

**iOS:** Use OSLog (built-in)

```swift
import OSLog

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    
    static let grocery = Logger(subsystem: subsystem, category: "Grocery")
    static let premium = Logger(subsystem: subsystem, category: "Premium")
    static let sync = Logger(subsystem: subsystem, category: "Sync")
}

// Usage:
Logger.grocery.info("handleItemHitZero - item: \(itemName), isPremium: \(isPremium)")
Logger.premium.warning("Premium check failed for household: \(householdId)")
```

**Benefits:**
- ✅ Searchable logs (`grep "\[Premium\]"`)
- ✅ Consistent format across codebase
- ✅ Easy to filter by level/category
- ✅ Timestamps for debugging timing issues

---

### 6. **Integration Tests (Server)**

#### Problem:
- No tests for critical paths
- `checkWritePermission()` bug would have been caught by tests
- Manual testing is slow and error-prone

#### Solution: Add Jest Tests

**Create:** `server/tests/premium.test.js`

```javascript
const request = require('supertest');
const app = require('../src/app');
const db = require('../src/models/database');
const { isHouseholdPremium, canWriteToHousehold } = require('../src/services/premiumService');

describe('Premium Service', () => {
    describe('canWriteToHousehold', () => {
        it('should allow single-member free household', () => {
            // Create test household with 1 member
            const householdId = createTestHousehold({ members: 1, premium: false });
            expect(canWriteToHousehold(householdId)).toBe(true);
        });
        
        it('should allow single-member premium household', () => {
            const householdId = createTestHousehold({ members: 1, premium: true });
            expect(canWriteToHousehold(householdId)).toBe(true);
        });
        
        it('should deny multi-member free household', () => {
            const householdId = createTestHousehold({ members: 2, premium: false });
            expect(canWriteToHousehold(householdId)).toBe(false);
        });
        
        it('should allow multi-member premium household', () => {
            const householdId = createTestHousehold({ members: 2, premium: true });
            expect(canWriteToHousehold(householdId)).toBe(true);
        });
        
        it('should deny expired premium', () => {
            const householdId = createTestHousehold({ 
                members: 2, 
                premium: true,
                expiresAt: '2020-01-01'  // Past date
            });
            expect(canWriteToHousehold(householdId)).toBe(false);
        });
    });
});

describe('Grocery API', () => {
    it('should allow single-member household to add item', async () => {
        const token = createTestToken({ householdId: 'single-member-household' });
        
        const res = await request(app)
            .post('/api/grocery')
            .set('Authorization', `Bearer ${token}`)
            .send({ name: 'Test Item' });
        
        expect(res.status).toBe(201);
    });
    
    it('should reject multi-member free household', async () => {
        const token = createTestToken({ householdId: 'multi-free-household' });
        
        const res = await request(app)
            .post('/api/grocery')
            .set('Authorization', `Bearer ${token}`)
            .send({ name: 'Test Item' });
        
        expect(res.status).toBe(403);
        expect(res.body.code).toBe('PREMIUM_REQUIRED');
    });
});
```

**Run tests:**
```bash
npm test
npm run test:coverage
```

**Benefits:**
- ✅ Catches regressions before deployment
- ✅ Documents expected behavior
- ✅ Confidence in refactoring
- ✅ CI/CD integration

---

### 7. **Client-Side Validation Consistency (iOS)**

#### Problem:
- Edit item validation added reactively
- Not all forms have validation
- Inconsistent patterns across views

#### Solution: Validation Protocol

**Create:** `ios/PantryPal/Protocols/Validatable.swift`

```swift
protocol Validatable {
    var isValid: Bool { get }
    var validationErrors: [ValidationError] { get }
}

struct ValidationError: Identifiable {
    let id = UUID()
    let field: String
    let message: String
}

// Example:
struct InventoryItemForm: Validatable {
    var quantity: Int
    var locationId: String?
    var expirationDate: Date?
    var hasExpiration: Bool
    
    var isValid: Bool {
        validationErrors.isEmpty
    }
    
    var validationErrors: [ValidationError] {
        var errors: [ValidationError] = []
        
        if quantity < 1 {
            errors.append(ValidationError(
                field: "quantity",
                message: "Quantity must be at least 1"
            ))
        }
        
        if locationId == nil || locationId?.isEmpty == true {
            errors.append(ValidationError(
                field: "location",
                message: "Please select a storage location"
            ))
        }
        
        return errors
    }
}
```

**Usage:**
```swift
@State private var form = InventoryItemForm(...)

var body: some View {
    Form {
        // ... fields ...
        
        if !form.validationErrors.isEmpty {
            Section {
                ForEach(form.validationErrors) { error in
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundColor(.red)
                        Text(error.message)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
    }
    .toolbar {
        Button("Save") {
            save()
        }
        .disabled(!form.isValid)  // ✅ Always enforced
    }
}
```

**Benefits:**
- ✅ Consistent validation across all forms
- ✅ Reusable validation logic
- ✅ Clear error messages
- ✅ Hard to bypass (disabled button)

---

## 📋 Priority Implementation Plan

### Phase 1: Critical (Do ASAP)
1. ✅ **Centralize `checkWritePermission()`** (Server)
   - Create `premiumService.js`
   - Replace all duplicated functions
   - **Prevents:** Permission bugs, inconsistent Premium checks
   - **Effort:** 2 hours

2. ✅ **Add validation middleware** (Server)
   - Create `validation.js`
   - Add to inventory/grocery routes
   - **Prevents:** Invalid data in database
   - **Effort:** 2 hours

3. ✅ **Create `GroceryService`** (iOS)
   - Move shared grocery logic
   - Use in all views
   - **Prevents:** Inconsistent grocery behavior
   - **Effort:** 1 hour

### Phase 2: Important (Before TestFlight)
4. ⚠️ **Add error code constants** (Both)
   - Create shared constants
   - Type-safe error handling
   - **Prevents:** Client/server mismatches
   - **Effort:** 1 hour

5. ⚠️ **Structured logging** (Both)
   - Logger utility on server
   - OSLog on iOS
   - **Prevents:** Hard-to-debug issues
   - **Effort:** 2 hours

### Phase 3: Nice-to-Have (Post-MVP)
6. 📝 **Integration tests** (Server)
   - Premium logic tests
   - API endpoint tests
   - **Prevents:** Regression bugs
   - **Effort:** 4-6 hours

7. 📝 **Validation protocol** (iOS)
   - Consistent form validation
   - Reusable across views
   - **Prevents:** Form submission bugs
   - **Effort:** 2 hours

---

## 🎯 Quick Wins (Do Today)

### 1. Move `checkWritePermission()` to shared file
**Effort:** 30 minutes  
**Impact:** Immediate consistency

### 2. Add `locationId` validation middleware
**Effort:** 15 minutes  
**Impact:** Prevents location bugs

### 3. Create `GroceryService.swift`
**Effort:** 30 minutes  
**Impact:** Fixes inconsistent grocery logic

**Total:** ~1.5 hours for major improvements!

---

## 📈 Long-Term Benefits

### Maintainability:
- Single place to update Premium logic
- Consistent patterns across codebase
- Self-documenting validation

### Bug Prevention:
- Type safety catches errors at compile time
- Tests catch regressions before deployment
- Validation at every layer

### Developer Experience:
- Easier onboarding (consistent patterns)
- Faster debugging (structured logs)
- Confidence in changes (tests + validation)

---

## 🎓 Lessons Learned from Recent Bugs

1. **Helper functions need tests** - `checkWritePermission()` logic error would have been caught
2. **Don't duplicate logic** - 3 copies of permission check = 3 places to fix bugs
3. **Validate at every layer** - Client validation + server validation = defense in depth
4. **Consistent logging saves time** - 🛒 emoji pattern made debugging much easier
5. **Type safety helps** - String error codes caused client/server mismatch

---

**Recommendation:** Start with Phase 1 (5 hours total) before TestFlight. This will prevent 80% of regression bugs with minimal effort.
