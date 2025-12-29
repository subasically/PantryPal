# PantryPal

A pantry inventory management app with barcode scanning, expiration tracking, and household sharing.

## ✅ Completed Features

### Server (Node.js + SQLite)
- [x] User authentication (email/password with JWT)
- [x] Password hashing with bcrypt (salted)
- [x] Household creation and management
- [x] Household invite codes with QR sharing
- [x] UPC barcode lookup via Open Food Facts API
- [x] Custom product creation with UPC
- [x] Inventory CRUD operations
- [x] Quantity adjustment (+/-)
- [x] Expiration date tracking
- [x] Expiring/expired item queries
- [x] Location management (hierarchical)
- [x] Checkout/consumption tracking with history
- [x] Consumption analytics/stats
- [x] **Grocery List** (with Premium auto-add/remove)
- [x] Full sync endpoint for offline support
- [x] Docker containerization
- [x] **74 automated tests** (Jest + Supertest)

### iOS App (Swift 6 / SwiftUI / iOS 18+)
- [x] Login/Register screens
- [x] **New User Onboarding Flow** (Create/Join/Skip)
- [x] Face ID biometric authentication
- [x] Sign in with Apple
- [x] Splash Screen
- [x] Barcode scanner (AVFoundation)
- [x] Inventory list view with search (name + brand)
- [x] Quick-add scanned items
- [x] Custom product form (when UPC not found)
- [x] Edit item view (quantity, expiration, location)
- [x] Quantity +/- controls with haptic feedback
- [x] Expiration date display with color coding
- [x] Location picker with default location memory
- [x] Checkout mode (quick scan to consume)
- [x] Pull-to-refresh
- [x] Filter by: All, Expiring Soon, Expired
- [x] Swipe-to-delete items
- [x] Custom color palette (Purple/Orange/Green)
- [x] Household sharing with invite codes + QR
- [x] **Premium Paywall & Limits**
- [x] **Grocery List** (with Premium auto-add)
- [x] Settings view with version info
- [x] Swift 6 strict concurrency compliance
- [x] Local Caching (SwiftData) - Phase 1

## 🚧 TODO Features

### Core (Priority)
- [ ] Push notifications for expiring items
- [ ] Background sync when online
- [ ] In-App Purchases (StoreKit integration)

### Nice to Have
- [ ] Product image display
- [ ] Barcode scan history
- [ ] Low stock alerts
- [ ] Category organization
- [ ] Search by category
- [ ] Dark mode theme refinement
- [ ] iPad layout optimization
- [ ] Widget for expiring items

### Advanced
- [ ] Recipe suggestions based on inventory
- [ ] Nutritional information display
- [ ] Export inventory to CSV
- [ ] Multi-level location sub-shelves
- [ ] iOS Reminders grocery list integration
- [ ] Amazon/Whole Foods cart links (affiliate revenue)

## 💰 Premium Model (Freemium)

**Free Tier:**
- Up to **25 inventory items**
- Up to **25 grocery items**
- Single user (or read-only household)
- All core features (scanning, expiration, offline)

**Premium Tier ($4.99/mo or $49.99/yr):**
- **Unlimited inventory items**
- **Unlimited grocery items**
- **Household Sharing** (Collaborative editing)
- **Auto-add to grocery** (when items run out)
- Priority sync reliability

### Premium Architecture

**Storage:** Premium status is stored on the `households` table, NOT on individual users.

```sql
-- households.is_premium = 0 (Free) or 1 (Premium)
CREATE TABLE households (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    is_premium INTEGER DEFAULT 0,
    created_at DATETIME
);
```

**Benefits:**
- **Household-wide:** One Premium subscription benefits all household members
- **Family Sharing:** Spouse/family members automatically get Premium when they join
- **Simple Billing:** One payment per household, not per user

**Example:**
```
Household: "Smith Family" (is_premium = 1)
    ├── User: John (pays $4.99/mo)     ← Premium ✓
    ├── User: Jane (joins household)   ← Premium ✓ (automatic)
    └── User: Kids (join household)    ← Premium ✓ (automatic)
```

**Enforcement:**
- Server checks `household.is_premium` before operations
- Free tier: `checkInventoryLimit()` and `checkGroceryLimit()` enforce 25 item limits
- Premium: Bypasses all limits

### Auto-Add to Grocery (Premium Feature)

When a Premium household runs out of an item, it's automatically added to the grocery list:

```javascript
// Triggered when inventory quantity reaches 0
function autoManageGrocery(householdId, productName, newQuantity, oldQuantity) {
    // Premium check
    if (!household.is_premium) return;
    
    // Item ran out (qty: 1 → 0)
    if (oldQuantity > 0 && newQuantity === 0) {
        // ✅ Auto-add to grocery list
    }
    
    // Item restocked (qty: 0 → 1+)
    if (oldQuantity === 0 && newQuantity > 0) {
        // ✅ Auto-remove from grocery list
    }
}
```

**User Experience:**
1. User taps [-] on "Milk" in Pantry (qty: 1 → 0)
2. Item removed from Pantry
3. **"Milk" automatically appears in Grocery tab** 🎉
4. User buys milk, scans barcode to add back
5. **"Milk" automatically removed from Grocery tab** 🎉

### Revenue Projections (after Apple's 15% cut)
| Users | Monthly | Annual |
|-------|---------|--------|
| 100 | $254 | $3,050 |
| 300 | $762 | $9,149 |
| 500 | $1,271 | $15,249 |
| 1,000 | $2,542 | $30,498 |

## Tech Stack
- **Server:** Node.js, Express, SQLite (better-sqlite3)
- **iOS App:** Swift 6, SwiftUI, AVFoundation (barcode scanning)
- **Auth:** JWT tokens, bcrypt password hashing, Face ID
- **Containerization:** Docker
- **Testing:** Jest, Supertest
- **Production:** VPS (62.146.177.62) via Docker Compose
- **API URL:** https://api-pantrypal.subasically.me

## Running Tests

```bash
cd server
npm test              # Run all 74 tests
npm run test:watch    # Watch mode
npm run test:coverage # With coverage report
```

**Test Coverage:**
- Auth API (15 tests): Register, login, JWT, household invites
- Inventory API (16 tests): CRUD, quantity adjustments, expiration
- Products API (12 tests): Custom products, UPC lookup
- Locations API (16 tests): Hierarchical locations, defaults
- Checkout API (14 tests): Scan checkout, history, stats

## Project Structure
```
PantryPal/
├── server/              # Node.js API server
│   ├── src/
│   │   ├── app.js       # Express app factory
│   │   ├── routes/      # API endpoints
│   │   ├── models/      # Database connection
│   │   ├── middleware/  # JWT auth
│   │   └── services/    # UPC lookup
│   ├── tests/           # Jest tests
│   ├── db/              # SQLite database & schema
│   ├── Dockerfile
│   └── docker-compose.yml
└── ios/                 # iOS SwiftUI app
    └── PantryPal/
        ├── Models/
        ├── Views/
        ├── ViewModels/
        ├── Services/
        └── Utils/       # Color palette
```

## Getting Started

### Server (Docker)
```bash
cd server
docker compose up -d
# API runs at http://localhost:3002
```

### Server (Local Development)
```bash
cd server
cp .env.example .env  # Configure your JWT secret
npm install
npm run dev           # Start with hot reload on port 3000
```

### iOS App
1. Open `ios/PantryPal.xcodeproj` in Xcode
2. Server is pre-configured to `https://api-pantrypal.subasically.me`
3. Select your device/simulator
4. Build and run (⌘R)

### Production Server
```bash
# SSH to production
ssh root@62.146.177.62

# Navigate to server
cd /root/pantrypal-server

# View logs
docker-compose logs -f pantrypal-api

# Restart server
docker-compose restart pantrypal-api

# Rebuild after code changes
docker-compose up -d --build --force-recreate
```

## API Endpoints
| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | /api/auth/register | Register new user |
| POST | /api/auth/login | Login |
| GET | /api/auth/me | Get current user |
| POST | /api/auth/household | Create household |
| POST | /api/auth/household/invite | Generate invite code |
| GET | /api/auth/household/invite/:code | Validate invite |
| POST | /api/auth/household/join | Join household |
| GET | /api/auth/household/members | List members |
| GET | /api/products/lookup/:upc | Lookup UPC |
| POST | /api/products | Create custom product |
| GET | /api/products | List products |
| PUT | /api/products/:id | Update product |
| GET | /api/inventory | Get all inventory |
| POST | /api/inventory | Add inventory item |
| POST | /api/inventory/quick-add | Scan & add item |
| PATCH | /api/inventory/:id/quantity | Adjust quantity |
| PUT | /api/inventory/:id | Update item |
| DELETE | /api/inventory/:id | Delete item |
| GET | /api/inventory/expiring | Get expiring items |
| GET | /api/inventory/expired | Get expired items |
| GET | /api/locations | Get locations |
| POST | /api/locations | Create location |
| PUT | /api/locations/:id | Update location |
| DELETE | /api/locations/:id | Delete location |
| POST | /api/checkout/scan | Checkout by UPC |
| GET | /api/checkout/history | Checkout history |
| GET | /api/checkout/stats | Consumption stats |
| GET | /api/sync/full | Full sync for offline |
| GET | /api/grocery | Get grocery list |
| POST | /api/grocery | Add item to grocery |
| DELETE | /api/grocery/:id | Remove from grocery |

## Color Palette
| Role | Color | Hex |
|------|-------|-----|
| Primary | Rebecca Purple | #5941A9 |
| Secondary | Orange | #F3A712 |
| Tertiary | Sage Green | #6D9F71 |

## License
ISC
