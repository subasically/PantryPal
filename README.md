# PantryPal

A pantry inventory management app with barcode scanning, expiration tracking, and household sharing. Built with a freemium model: **25 items free, unlimited with Premium ($4.99/mo)**.

## 🎯 Project Status

**Current Phase:** Revenue Validation (Week 2)  
**Next Priority:** In-App Purchases (StoreKit 2)  
**Production:** https://api-pantrypal.subasically.me  
**Server:** VPS 62.146.177.62 (`/root/pantrypal-server`)

### Recent Milestones
- ✅ **Premium Lifecycle Management** (Dec 30): Graceful expiration, downgrade flow, offline caching
- ✅ **Grocery Auto-Remove** (Dec 31): UPC + name matching, auto-remove on restock
- ✅ **Location & TextField Standardization** (Dec 30): 44pt minimum heights, validated defaults
- ✅ **Centralized Toast System** (Dec 30): Queue management, haptic feedback, iPad support
- ✅ **74 Backend Tests** + **11 UI Tests** (ongoing improvements)

## ✅ Completed Features

### Server (Node.js 20 + SQLite)
- [x] Authentication (Email/Password + Apple Sign In with JWT)
- [x] Password hashing (bcrypt with salts)
- [x] Household multi-tenancy (`household_id` scoping)
- [x] Household creation, invites with QR codes
- [x] **Premium lifecycle** (`premium_expires_at`, graceful downgrade)
- [x] UPC barcode lookup (Open Food Facts API)
- [x] Custom product creation with UPC
- [x] Inventory CRUD with quantity +/- adjustments
- [x] Expiration tracking (color-coded: green/yellow/red)
- [x] Location management (hierarchical, sticky defaults)
- [x] Checkout/consumption tracking with history
- [x] Consumption analytics
- [x] **Grocery List** with Premium auto-add/auto-remove
- [x] Full sync endpoint (offline-first support)
- [x] Docker containerization
- [x] **74 automated tests** (Jest + Supertest)

### iOS App (Swift 6 / SwiftUI / iOS 18+)
- [x] Login/Register screens (standardized TextFields)
- [x] **New User Onboarding Flow** (Create/Join/Skip household)
- [x] Face ID biometric authentication
- [x] Sign in with Apple
- [x] Barcode scanner (AVFoundation)
- [x] Inventory list with search (name + brand)
- [x] Quick-add scanned items
- [x] Custom product form (when UPC not found)
- [x] Edit item view (quantity, expiration, location)
- [x] Quantity +/- with haptic feedback
- [x] Expiration date display (color-coded)
- [x] Location picker with sticky defaults
- [x] Checkout mode (quick scan to consume)
- [x] Pull-to-refresh
- [x] Filters: All, Expiring Soon, Expired
- [x] Swipe-to-delete
- [x] Custom color palette (Rebecca Purple/Orange/Sage Green)
- [x] Household sharing with invite codes + QR
- [x] **Premium Paywall** (25 item limits)
- [x] **Grocery List** with Premium auto-add/remove
- [x] Settings with version info + Premium badge
- [x] Swift 6 strict concurrency compliance
- [x] SwiftData local caching (offline-first)
- [x] Centralized Toast system
- [x] Confetti + Haptic feedback

## 🚧 Next Steps

### Immediate (Week 2)
- [ ] **In-App Purchases (StoreKit 2)** ← NEXT
  - Monthly: $4.99 (`com.pantrypal.premium.monthly`)
  - Annual: $49.99 (`com.pantrypal.premium.annual`)
  - See [STOREKIT_PLAN.md](./STOREKIT_PLAN.md) for full implementation plan
- [ ] One-time "household locked" banner (free users)
- [ ] Restore purchases flow

### Future Priorities
- [ ] Push notifications (expiring items)
- [ ] Background sync when online
- [ ] Product image display
- [ ] Barcode scan history
- [ ] Low stock alerts

### Future Enhancements (Post-Revenue)
- [ ] Recipe suggestions based on inventory
- [ ] Nutritional information display
- [ ] Export inventory to CSV
- [ ] Category organization + search
- [ ] iOS Reminders integration
- [ ] Dark mode refinement
- [ ] iPad layout optimization
- [ ] Widget for expiring items

## 💰 Premium Model (Freemium - Household-Level)

### Free Tier
- Up to **25 inventory items**
- Up to **25 grocery items**
- Single user OR read-only household access
- All core features (scanning, expiration tracking, offline mode)

### Premium Tier ($4.99/mo or $49.99/yr)
- ✨ **Unlimited inventory items**
- ✨ **Unlimited grocery items**
- ✨ **Household Sharing** (Collaborative editing for all members)
- ✨ **Auto-add to grocery** (items at qty=0 auto-added)
- ✨ **Auto-remove from grocery** (restocked items auto-removed)
- Priority sync reliability

### Architecture: Household-Level Premium

Premium status is stored on `households` table, NOT individual users:

```sql
CREATE TABLE households (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    is_premium INTEGER DEFAULT 0,
    premium_expires_at DATETIME,  -- NULL = free, past date = expired
    created_at DATETIME
);
```

**Benefits:**
- **Family Sharing:** One Premium subscription benefits ALL household members
- **Simple Billing:** One payment per household, not per user
- **Graceful Downgrade:** Premium remains active until `premium_expires_at`

**Example:**
```
Household: "Smith Family" (is_premium=1, expires=2026-02-01)
    ├── User: John (pays $4.99/mo)     ← Premium ✓
    ├── User: Jane (joins household)   ← Premium ✓ (automatic)
    └── User: Kids (join household)    ← Premium ✓ (automatic)
```

### Premium Enforcement

Server uses `premiumHelper.js` for consistent Premium checks:

```javascript
// Check if household has active Premium
function isPremium(household) {
    if (!household.is_premium) return false;
    if (!household.premium_expires_at) return true; // Legacy Premium
    return new Date(household.premium_expires_at) > new Date();
}
```

**Limits:**
- Free: `checkInventoryLimit()` and `checkGroceryLimit()` enforce 25 items before INSERT/UPDATE
- Premium: Bypasses all limits
- Expired Premium: Read-only above limits (no deletion, graceful degradation)

### Auto-Add/Remove (Premium Only)

When Premium users run out of items, they're auto-added to grocery list:

```javascript
// Triggered on inventory quantity change
function autoManageGrocery(householdId, product, newQty, oldQty) {
    if (!isPremium(household)) return;
    
    // Ran out (qty: 1+ → 0)
    if (oldQty > 0 && newQty === 0) {
        // ✅ Auto-add to grocery list (unless already there)
    }
    
    // Restocked (qty: 0 → 1+)
    if (oldQty === 0 && newQty > 0) {
        // ✅ Auto-remove from grocery list (UPC or name match)
    }
}
```

**User Experience:**
1. User taps `[-]` on "Milk" in Pantry (qty: 1 → 0)
2. Item removed from Pantry
3. 🎉 **"Milk" automatically appears in Grocery tab**
4. User buys milk, scans barcode to add back (qty: 0 → 1)
5. 🎉 **"Milk" automatically removed from Grocery tab**
6. Toast notification confirms both actions

### Revenue Projections (after Apple's 15% cut)

| Users | Monthly | Annual |
|-------|---------|--------|
| 100   | $254    | $3,050 |
| 300   | $762    | $9,149 |
| 500   | $1,271  | $15,249 |
| 1,000 | $2,542  | $30,498 |

## 🛠 Tech Stack

### Backend
- **Runtime:** Node.js 20 (Alpine Docker)
- **Framework:** Express 5.x (CommonJS modules)
- **Database:** SQLite (better-sqlite3 - synchronous)
- **Auth:** JWT tokens + bcrypt password hashing
- **External APIs:** Open Food Facts (UPC lookup)
- **Testing:** Jest + Supertest (74 tests, 98%+ coverage)
- **Deployment:** Docker Compose on VPS

### iOS
- **Language:** Swift 6 (Strict Concurrency)
- **UI Framework:** SwiftUI (iOS 18+)
- **Architecture:** MVVM with @Observable ViewModels
- **Local Storage:** SwiftData (caching) + UserDefaults (auth)
- **Camera:** AVFoundation (barcode scanning)
- **Auth:** AuthenticationServices (Sign in with Apple)
- **Payments:** StoreKit 2 (in progress)
- **Testing:** XCTest (11 UI tests)

### Infrastructure
- **Production Server:** VPS at 62.146.177.62 (`/root/pantrypal-server`)
- **Production API:** https://api-pantrypal.subasically.me
- **Test Server:** localhost:3002 (for UI tests)
- **Containerization:** Docker + Docker Compose
- **Deployment:** rsync/scp (no Git on production)

## 🧪 Testing

### Backend Tests (74 tests, Jest + Supertest)

```bash
cd server
npm test              # Run all tests
npm run test:watch    # Watch mode
npm run test:coverage # Coverage report (98%+)
```

**Test Suites:**
- `auth.test.js` (15 tests): Register, login, JWT validation, household invites, Apple Sign In
- `inventory.test.js` (16 tests): CRUD, quantity adjustments, expiration queries, location validation
- `products.test.js` (12 tests): Custom products, UPC lookup, duplicate handling
- `locations.test.js` (16 tests): Hierarchical locations, defaults, deletion constraints
- `checkout.test.js` (14 tests): Scan checkout, history, consumption stats, auto-add to grocery
- `grocery.test.js` (new): Auto-add/remove, Premium checks, UPC + name matching

### iOS UI Tests (11 tests, XCTest)

**Prerequisites:**
1. Start test server: `npm run test:server` (port 3002)
2. Seed test user: `test@pantrypal.com` / `Test123!`
3. Run tests in Xcode: Product → Test (⌘U)

**Test Suites:**
- Login/Logout flow
- Inventory CRUD operations
- Barcode scanning simulation
- Location management
- Filter application
- Household switching
- Settings navigation

**Known Issues:**
- UI tests have timing sensitivity (use `sleep(2)` for animations)
- Accessibility identifiers must match between app and tests
- Test server must be running on localhost:3002

See [UI_TESTING_GUIDE.md](./UI_TESTING_GUIDE.md) for full debugging procedures.

## 📁 Project Structure

```
PantryPal/
├── .github/
│   ├── agents/                # AI agent documentation (backend, devops, iOS, testing)
│   ├── skills/                # Condensed skill versions for GitHub/Claude
│   └── copilot-instructions.md
├── server/                    # Node.js API server
│   ├── src/
│   │   ├── app.js             # Express app factory
│   │   ├── index.js           # Server entry point
│   │   ├── routes/            # API endpoints (auth, inventory, grocery, etc.)
│   │   ├── models/            # Database connection (better-sqlite3)
│   │   ├── middleware/        # JWT authentication
│   │   ├── services/          # External APIs (UPC lookup)
│   │   └── utils/             # Premium helpers, limit checks
│   ├── tests/                 # Jest test suites (74 tests)
│   ├── db/
│   │   ├── schema.sql         # SQLite database schema
│   │   └── pantrypal.db       # Local database (gitignored)
│   ├── Dockerfile
│   ├── docker-compose.yml     # Production compose
│   ├── docker-compose.test.yml # Test server compose
│   └── package.json
├── ios/                       # iOS SwiftUI app
│   ├── PantryPal/
│   │   ├── Models/            # API models + SwiftData cache models
│   │   ├── Views/             # SwiftUI views (Inventory, Grocery, Settings, etc.)
│   │   ├── ViewModels/        # @Observable ViewModels (MVVM pattern)
│   │   ├── Services/          # APIService, SyncService, BiometricAuth, etc.
│   │   ├── Utils/             # Color palette, ToastCenter, HapticService
│   │   ├── Resources/         # Audio files (scan sounds)
│   │   └── Assets.xcassets/   # App icons, colors
│   ├── PantryPal.xcodeproj/
│   └── PantryPalUITests/      # XCTest UI tests (11 tests)
├── test-plans/                # Detailed test plans (free/premium, regression)
├── scripts/                   # Helper scripts (start-test-server.sh)
├── DEPLOYMENT.md              # Production deployment guide
├── SERVER_COMMANDS.md         # Quick reference for server ops
├── STOREKIT_PLAN.md           # In-App Purchase implementation plan
├── TODO.md                    # Current sprint tasks
└── README.md                  # This file
```

### Key File Locations

**Server:**
- Database schema: [server/db/schema.sql](server/db/schema.sql)
- Premium logic: [server/src/utils/premiumHelper.js](server/src/utils/premiumHelper.js)
- Auth middleware: [server/src/middleware/auth.js](server/src/middleware/auth.js)
- Routes: [server/src/routes/](server/src/routes/)

**iOS:**
- App entry: [ios/PantryPal/PantryPalApp.swift](ios/PantryPal/PantryPalApp.swift)
- API models: [ios/PantryPal/Models/Models.swift](ios/PantryPal/Models/Models.swift)
- SwiftData cache: [ios/PantryPal/Models/SwiftDataModels.swift](ios/PantryPal/Models/SwiftDataModels.swift)
- API service: [ios/PantryPal/Services/APIService.swift](ios/PantryPal/Services/APIService.swift)

## 🚀 Getting Started

### Server (Docker - Recommended)

```bash
cd server
docker compose up -d
# API runs at http://localhost:3002
```

### Server (Local Development)

```bash
cd server
cp .env.example .env  # Configure JWT_SECRET
npm install
npm run dev           # Hot reload on port 3000
```

**Environment Variables (.env):**
```bash
JWT_SECRET=your-secret-key-here  # Generate with: openssl rand -base64 32
PORT=3000                        # Local dev port (production uses 3002 in Docker)
```

### iOS App

1. Open `ios/PantryPal.xcodeproj` in Xcode
2. Select target device/simulator
3. Build and run (⌘R)

**Test Credentials:**
- Email: `test@pantrypal.com`
- Password: `Test123!`
- Household: Pre-seeded with test data

### Production Server Access

```bash
# SSH to production
ssh root@62.146.177.62

# Navigate to server directory
cd /root/pantrypal-server

# View logs
docker-compose logs -f pantrypal-api

# Restart server
docker-compose restart pantrypal-api

# Rebuild after code changes
docker-compose up -d --build --force-recreate
```

**Deploy Code Changes:**

```bash
# From local machine, sync files to production
rsync -avz --exclude='node_modules' --exclude='db/pantrypal.db' \
  server/ root@62.146.177.62:/root/pantrypal-server/

# Then SSH to production and rebuild
ssh root@62.146.177.62
cd /root/pantrypal-server
docker-compose up -d --build --force-recreate
```

See [DEPLOYMENT.md](./DEPLOYMENT.md) and [SERVER_COMMANDS.md](./SERVER_COMMANDS.md) for complete deployment procedures.

## 📡 API Endpoints

### Authentication
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/auth/register` | Register new user (email/password or Apple ID) |
| POST | `/api/auth/login` | Login with email/password |
| POST | `/api/auth/apple` | Sign in with Apple |
| GET | `/api/auth/me` | Get current user + household info |
| POST | `/api/auth/household` | Create new household |
| POST | `/api/auth/household/invite` | Generate invite code |
| GET | `/api/auth/household/invite/:code` | Validate invite code |
| POST | `/api/auth/household/join` | Join household with code |
| GET | `/api/auth/household/members` | List household members |
| POST | `/api/auth/household/switch` | Switch to different household |

### Products
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/products/lookup/:upc` | Lookup product by UPC (Open Food Facts) |
| POST | `/api/products` | Create custom product |
| GET | `/api/products` | List all household products |
| PUT | `/api/products/:id` | Update product |

### Inventory
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/inventory` | Get all inventory items (household-scoped) |
| POST | `/api/inventory` | Add inventory item |
| POST | `/api/inventory/quick-add` | Scan & add item (barcode shortcut) |
| PATCH | `/api/inventory/:id/quantity` | Adjust quantity (+/-) |
| PUT | `/api/inventory/:id` | Update item (expiration, location, etc.) |
| DELETE | `/api/inventory/:id` | Delete item |
| GET | `/api/inventory/expiring` | Get items expiring within 7 days |
| GET | `/api/inventory/expired` | Get items past expiration |

### Locations
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/locations` | Get hierarchical locations |
| POST | `/api/locations` | Create location |
| PUT | `/api/locations/:id` | Update location |
| DELETE | `/api/locations/:id` | Delete location (if no inventory) |

### Checkout
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/api/checkout/scan` | Checkout item by UPC (decrement qty) |
| GET | `/api/checkout/history` | Get checkout history |
| GET | `/api/checkout/stats` | Consumption statistics |

### Grocery List
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/grocery` | Get grocery list |
| POST | `/api/grocery` | Add item to grocery list |
| DELETE | `/api/grocery/:id` | Remove item from grocery |
| DELETE | `/api/grocery/by-upc/:upc` | Remove by UPC (auto-remove helper) |
| DELETE | `/api/grocery/by-name/:name` | Remove by name (auto-remove helper) |

### Sync & Admin
| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/sync/full` | Full sync (users, inventory, locations, grocery) |
| GET | `/api/health` | Health check |
| POST | `/api/admin/premium` | Set Premium status (DEBUG only) |

### Response Format

**Success (200):**
```json
{
    "user": { "id": "...", "email": "...", "householdId": "..." },
    "household": { "id": "...", "name": "...", "isPremium": true }
}
```

**Error (400/403/404/500):**
```json
{
    "error": "Error message",
    "code": "LIMIT_REACHED"  // Optional error code
}
```

**Error Codes:**
- `LIMIT_REACHED`: Free tier hit 25 item limit
- `PREMIUM_REQUIRED`: Feature requires Premium subscription
- `NO_WRITE_ACCESS`: User doesn't have household write permission

## 🎨 Design System

### Color Palette
| Role | Color | Hex | Usage |
|------|-------|-----|-------|
| Primary | Rebecca Purple | `#5941A9` | Buttons, accents, Premium badges |
| Secondary | Orange | `#F3A712` | Highlights, warnings, expiring items |
| Tertiary | Sage Green | `#6D9F71` | Success states, fresh items |

### Expiration Color Coding
- **Green:** More than 7 days until expiration (fresh)
- **Yellow/Orange:** 3-7 days until expiration (expiring soon)
- **Red:** Expired or less than 3 days (urgent)

### Typography & Spacing
- **Minimum Touch Target:** 44pt (Apple HIG standard)
- **TextField Height:** 44pt minimum (standardized across app)
- **Corner Radius:** 12pt (buttons, cards, modals)
- **Padding:** 16pt (standard content padding)

### Animations
- **Toast:** Slide-down from top (0.3s spring animation)
- **Modal:** Slide-up from bottom (default SwiftUI sheet)
- **Confetti:** Particle system on milestone events
- **Pull-to-Refresh:** Native SwiftUI refreshable

### Haptic Feedback
- **Success:** Light impact (item added, checkout complete)
- **Error:** Heavy impact (limit reached, validation failed)
- **Quantity Change:** Selection feedback (+/- button taps)
- **Delete:** Medium impact (swipe-to-delete)

---

## 🧑‍💻 Development Guidelines

### Backend (Node.js)

**Coding Style:**
- CommonJS modules (`require`/`module.exports`)
- 4-space indentation
- camelCase for variables/functions
- Route files named after resources (e.g., `inventory.js`, `grocery.js`)

**Database Access:**
- Use `better-sqlite3` **synchronously** (no async/await needed)
- Always scope queries by `household_id`
- Use prepared statements for SQL injection protection
- Check Premium limits BEFORE INSERT/UPDATE

**Authentication:**
- JWT middleware: `const authenticateToken = require('../middleware/auth')`
- Attach user to `req.user` after validation
- Check household Premium status via `premiumHelper.isPremium(household)`

**Error Handling:**
```javascript
// Return structured errors with codes
return res.status(403).json({ 
    error: 'Free tier limited to 25 items', 
    code: 'LIMIT_REACHED' 
});
```

### iOS (Swift + SwiftUI)

**Coding Style:**
- Swift 6 strict concurrency (`Sendable`, `@MainActor`)
- 4-space indentation
- Types in UpperCamelCase, properties/functions in lowerCamelCase
- Files match main type name

**Architecture:**
- MVVM pattern with `@Observable` ViewModels
- Repository pattern: ViewModel → Service → API
- SwiftData for local caching (offline-first)

**Common Imports:**
```swift
import SwiftUI
import SwiftData  // REQUIRED for @Query, FetchDescriptor, modelContext
```

**Error Handling:**
```swift
// APIError is FILE-LEVEL, NOT nested in APIService
enum APIError: LocalizedError {
    case unauthorized
    case limitReached
    case premiumRequired
}
```

**Accessibility:**
- Always add `.accessibilityIdentifier()` for UI test targets
- Format: `"{component}_{action}"` (e.g., `"inventory_addButton"`)

### Git Workflow

**Commit Messages (Conventional Commits):**
```
feat: Add grocery auto-remove on restock
fix: Resolve location validation bug in inventory
docs: Update DEPLOYMENT.md with new env vars
test: Add checkout auto-add test cases
chore: Bump version to 1.0.1
```

**Branching:**
- `main` = production-ready code
- Feature branches: `feature/grocery-auto-remove`
- Hotfix branches: `hotfix/login-crash`

---

## ⚠️ Known Issues & Gotchas

### Server
1. **New Users & Households:**
   - New users created via Apple Sign In do NOT have `household_id` initially
   - Must show onboarding flow: Create/Join/Skip household
   
2. **Database Schema:**
   - If schema changes, Docker volume must be updated or tables dropped
   - Run migrations: `docker-compose exec pantrypal-api node /app/migration.js`

3. **Auth Middleware:**
   - Use default export: `require('../middleware/auth')`, NOT named export
   - Import as: `const authenticateToken = require('../middleware/auth')`

4. **Premium Logic:**
   - Always use `premiumHelper.isPremium(household)` for consistency
   - Check `premium_expires_at` for graceful expiration (don't just check `is_premium`)

### iOS
1. **SwiftData Import:**
   - Files using `@Query`, `FetchDescriptor`, or `modelContext` MUST import SwiftData
   - Error: "Cannot find type 'FetchDescriptor' in scope" = missing import

2. **APIError Location:**
   - `APIError` enum is FILE-LEVEL (NOT inside `APIService` class)
   - Use `APIError.unauthorized`, NOT `APIService.APIError.unauthorized`

3. **AuthViewModel Properties:**
   - Use `currentUser` and `currentHousehold` (NOT `user` or `householdInfo`)

4. **SwiftData Models:**
   - Grocery: `SDGroceryItem` (SwiftData cache)
   - Inventory: `SDInventoryItem` (SwiftData cache)
   - API Models: `GroceryItem`, `InventoryItem` (from server)

5. **Loading States:**
   - Ensure spinners persist for at least 1.5s to prevent UI flashing
   - Use `Task.sleep(nanoseconds: 500_000_000)` for minimum durations

### Production Deployment
1. **Server Directory:**
   - Production path: `/root/pantrypal-server` (NOT a Git repo)
   - Use `rsync` or `scp` to copy files, then rebuild Docker container

2. **Database Backups:**
   - SQLite database: `/root/pantrypal-server/db/pantrypal.db`
   - Backup before schema changes: `cp pantrypal.db pantrypal.db.backup`

3. **Environment Variables:**
   - Production `.env` must have strong `JWT_SECRET`
   - Generate with: `openssl rand -base64 32`

---

## 📚 Additional Documentation

- [DEPLOYMENT.md](./DEPLOYMENT.md) - Complete deployment procedures + rollback
- [SERVER_COMMANDS.md](./SERVER_COMMANDS.md) - Quick reference for server operations
- [STOREKIT_PLAN.md](./STOREKIT_PLAN.md) - In-App Purchase implementation plan
- [TODO.md](./TODO.md) - Current sprint tasks and priorities
- [AGENTS.md](./AGENTS.md) - Repository guidelines for AI agents
- [UI_TESTING_GUIDE.md](./UI_TESTING_GUIDE.md) - XCTest debugging procedures
- [.github/agents/](/.github/agents/) - Detailed agent documentation (backend, devops, iOS, testing)
- [.github/skills/](/.github/skills/) - Quick reference skills for GitHub/Claude

---

## 📄 License

ISC
