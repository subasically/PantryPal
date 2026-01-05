# PantryPal Architecture Reference

Quick reference for PantryPal's architecture and patterns.

## Tech Stack

### Server
- **Runtime:** Node.js 20 (Alpine Docker)
- **Database:** SQLite (better-sqlite3, synchronous)
- **Auth:** JWT + Apple Sign In + Email/Password
- **Architecture:** REST API, Controller/Service pattern
- **Deployment:** Docker Compose on VPS
- **URL:** https://api-pantrypal.subasically.me

### iOS App
- **Language:** Swift 6 (Strict Concurrency)
- **UI:** SwiftUI (iOS 18+)
- **Architecture:** MVVM + Repository/Service
- **Local Data:** SwiftData (caching) + UserDefaults (auth)
- **Key Libraries:** AVFoundation (scanning), AuthenticationServices

## Project Structure

```
PantryPal/
├── server/
│   ├── src/
│   │   ├── controllers/     # Request handlers
│   │   ├── services/        # Business logic
│   │   ├── middleware/      # Auth, validation
│   │   ├── routes/          # API routes
│   │   └── app.js           # Express app
│   ├── Dockerfile
│   └── docker-compose.yml
│
├── ios/
│   └── PantryPal/
│       ├── Views/           # SwiftUI views
│       ├── ViewModels/      # MVVM view models
│       ├── Services/        # API, Auth, Sync
│       ├── Models/          # SwiftData models
│       └── Utils/           # Helpers, extensions
│
├── scripts/                 # Helper scripts
└── .github/skills/          # Copilot skills
```

## Key Patterns

### 1. Free vs Premium
```javascript
// Server constants
const FREE_LIMIT = 25;  // Max items for free tier

// Premium features:
// - Unlimited items
// - Household sharing (write access)
// - Auto-add to grocery
```

### 2. Household Model
```javascript
// users.household_id is NULLABLE
// - NULL = new user, no household yet
// - value = member of household

// New user flow:
// 1. Register/Login → household_id = NULL
// 2. AuthViewModel auto-creates household in background
// 3. If auto-creation fails, show HouseholdSetupView
// 4. User MUST create or join household (no skip option)
// 5. HouseholdSetupView dismisses only after household_id is set

// CRITICAL: Never dismiss HouseholdSetupView without calling
// await authViewModel.completeHouseholdSetup() first!
```

### 3. Sync Strategy
```swift
// iOS uses bidirectional sync
// - Upload: Local SwiftData → Server SQLite
// - Download: Server SQLite → Local SwiftData
// - Conflict resolution: Server wins
// - Offline: Queue changes locally

// Sync Debugging:
// 1. Check sync_log table for correct entity_id/action values
// 2. Verify syncLogger parameter order matches call sites
// 3. Use Settings → Debug → Force Full Sync to clear stuck cursor
// 4. Multi-device issues often invisible in single-device dev
// 5. Console logs: Look for "Received X changes" and "Applied X changes"
```

### 4. Authentication
```swift
// iOS stores token in UserDefaults
UserDefaults.standard.string(forKey: "authToken")

// Server validates with JWT middleware
// File: server/src/middleware/auth.js
module.exports = authenticateToken  // Default export!
```

### 5. SwiftData Caching
```swift
// Inventory items: SDInventoryItem
// Grocery items: SDGroceryItem

// ALWAYS import SwiftData when using:
// - @Query
// - FetchDescriptor
// - modelContext.fetch()
```

## Common Gotchas

### 1. Auth Middleware Import
```javascript
// ✅ CORRECT (default export)
const authenticateToken = require('../middleware/auth');

// ❌ WRONG (named export)
const { authenticateToken } = require('../middleware/auth');
```

### 2. SwiftData Import
```swift
// ✅ CORRECT
import SwiftData
let items = try modelContext.fetch(FetchDescriptor<SDInventoryItem>())

// ❌ WRONG (missing import)
let items = try modelContext.fetch(FetchDescriptor<SDInventoryItem>())
// Error: "Cannot find type 'FetchDescriptor' in scope"
```

### 3. APIError Usage
```swift
// ✅ CORRECT (file-level enum)
throw APIError.unauthorized

// ❌ WRONG (not nested in class)
throw APIService.APIError.unauthorized
```

### 4. New Users
```javascript
// New users don't have households!
// Check user.household_id before household operations
if (!user.household_id) {
    return res.status(400).json({ error: "No household" });
}
```

### 5. Premium Checks
```javascript
// Server-side limit checks
function checkInventoryLimit(userId, db) {
    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
    const household = user.household_id 
        ? db.prepare('SELECT * FROM households WHERE id = ?').get(user.household_id)
        : null;
    
    if (household?.is_premium) return true;  // Unlimited
    
    const count = db.prepare(
        'SELECT COUNT(*) as count FROM inventory WHERE user_id = ?'
    ).get(userId).count;
    
    return count < FREE_LIMIT;
}
```

## Database Schema

### Users Table
```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    email TEXT UNIQUE,
    password_hash TEXT,
    apple_id TEXT UNIQUE,
    display_name TEXT,
    household_id INTEGER,  -- NULLABLE!
    created_at DATETIME,
    FOREIGN KEY (household_id) REFERENCES households(id)
);
```

### Households Table
```sql
CREATE TABLE households (
    id INTEGER PRIMARY KEY,
    name TEXT,
    join_code TEXT UNIQUE,
    is_premium INTEGER DEFAULT 0,  -- 0 = false, 1 = true
    created_at DATETIME
);
```

## API Endpoints

### Auth
- `POST /api/auth/register` - Email registration
- `POST /api/auth/login` - Email login
- `POST /api/auth/apple` - Apple Sign In
- `GET /api/auth/me` - Get current user

### Inventory
- `GET /api/inventory` - List items
- `POST /api/inventory` - Add item (checks limit)
- `PUT /api/inventory/:id` - Update item
- `DELETE /api/inventory/:id` - Delete item

### Grocery
- `GET /api/grocery` - List items
- `POST /api/grocery` - Add item (checks limit)
- `PUT /api/grocery/:id` - Update item
- `DELETE /api/grocery/:id` - Delete item

### Test Endpoints (local only)
- `GET /api/test/status` - Test server status
- `POST /api/test/reset` - Reset test data
- `POST /api/test/seed` - Seed test data

## Environment Variables

### Server
```bash
NODE_ENV=production
PORT=3000
JWT_SECRET=your-secret
DATABASE_PATH=/app/data/pantrypal.db

# Test endpoints (local only)
ALLOW_TEST_ENDPOINTS=true
TEST_ADMIN_KEY=test-key
```

### iOS
```swift
// Hard-coded in APIService.swift
private let baseURL: String = {
    #if DEBUG
    return "http://localhost:3002/api"  // Test server
    #else
    return "https://api-pantrypal.subasically.me/api"  // Production
    #endif
}()
```

## Test Infrastructure

### Test Server
- **Port:** 3002 (not 3000!)
- **Start:** `./scripts/start-test-server.sh`
- **Test user:** test@pantrypal.com / Test1234!
- **Database:** Separate from production

### UI Tests
- **Location:** `ios/PantryPalUITests/`
- **Simulator:** DEA4C9CE-5106-41AD-B36A-378A8714D172 (iPhone 16)
- **Pass rate:** 36% (4/11 tests)
- **Run:** See `run-ui-tests.md` skill

## Pro Tips
- Always check user.household_id before household operations
- Premium checks happen server-side (not client)
- SwiftData imports required for @Query
- Test server runs on port 3002, not 3000
- Physical device testing requires passcode (use simulator)
- Logout between tests uses settings.button + settings.signOutButton
- Database is synchronous (better-sqlite3) - no async/await needed
