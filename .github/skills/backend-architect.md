# Backend Architecture & API Development

Expert guidance for designing and implementing PantryPal server features.

## When to Use
- Adding new API endpoints
- Modifying database schema
- Implementing business logic
- Debugging server issues
- Questions about server architecture

## Tech Stack
- **Runtime:** Node.js 20 (CommonJS)
- **Framework:** Express 5.x
- **Database:** SQLite (better-sqlite3, synchronous)
- **Auth:** JWT + Apple Sign In + Email/Password
- **Logging:** Winston (JSON in production, console in dev)
- **Rate Limiting:** express-rate-limit
- **Testing:** Jest + Supertest (84 tests, 100% pass rate)
- **Production:** Docker Compose on VPS (62.146.177.62)
- **Development:** Database reset: `./server/scripts/reset-database.sh`
- **Testing Guide:** Follow structured test plan in `TESTING.md`

## Quick Reference

### Project Structure
```
server/
├── src/
│   ├── app.js              # Express app factory
│   ├── routes/             # REST endpoints (Controller layer)
│   ├── services/           # Business logic layer (NEW)
│   │   ├── authService.js, inventoryService.js, etc.
│   ├── models/database.js  # SQLite connection
│   ├── middleware/         # Auth, logging, rate limiting
│   └── utils/              # premiumHelper, logger (Winston)
├── logs/                   # Winston logs (gitignored)
├── scripts/                # backup-database.sh, restore-database.sh
└── db/schema.sql           # Database schema
```

### Service Layer Pattern (NEW - Jan 2026)
```javascript
// Route (Controller) - HTTP concerns only
const express = require('express');
const authenticateToken = require('../middleware/auth');
const inventoryService = require('../services/inventoryService');
const router = express.Router();

router.use(authenticateToken);

router.get('/', async (req, res) => {
    try {
        const items = await inventoryService.getAllInventory(req.user.householdId);
        res.json(items);
    } catch (error) {
        const status = error.message.includes('not found') ? 404 : 500;
        res.status(status).json({ error: error.message });
    }
});

module.exports = router;
```

```javascript
// Service - Business logic, reusable, no HTTP dependencies
const db = require('../models/database');
const logger = require('../utils/logger');

/**
 * Get all inventory items for a household
 * @param {string} householdId - Household ID
 * @returns {Array} Inventory items
 */
function getAllInventory(householdId) {
    logger.debug('Fetching inventory', { householdId });
    return db.prepare('SELECT * FROM inventory WHERE household_id = ?').all(householdId);
}

module.exports = { getAllInventory };
```
        res.status(500).json({ error: 'Failed to fetch items' });
    }
});

module.exports = router;
```

### Database Access (Synchronous)
```javascript
// Read
const item = db.prepare('SELECT * FROM inventory WHERE id = ?').get(id);
const items = db.prepare('SELECT * FROM inventory WHERE household_id = ?').all(householdId);

// Write
db.prepare('INSERT INTO inventory (id, product_id, household_id) VALUES (?, ?, ?)')
  .run(id, productId, householdId);

// Update
db.prepare('UPDATE inventory SET quantity = ? WHERE id = ?').run(newQuantity, id);
```

### Freemium Logic
```javascript
const { isHouseholdPremium, canAddItems } = require('../utils/premiumHelper');

// Check before INSERT
if (!isHouseholdPremium(householdId) && !canAddItems(householdId, 'inventory', 1)) {
    return res.status(403).json({ 
        error: 'free_limit_reached',
        limit: 25,
        upgrade_required: true 
    });
}
```

### Authentication Flow
```javascript
// Middleware sets req.user from JWT
// Always validate householdId for household-scoped data
router.get('/items', (req, res) => {
    const { householdId } = req.user;
    if (!householdId) {
        return res.status(400).json({ error: 'No household' });
    }
    // ... query with householdId
});
```

### Winston Logging (NEW)
```javascript
const logger = require('../utils/logger');

// Use appropriate log levels
logger.info('User logged in', { userId, householdId });
logger.error('Database error', { error: error.message });
logger.debug('Premium check', { householdId, isPremium });

// Auth events automatically logged by authService
// Premium checks automatically logged by premiumHelper
```

### Rate Limiting (NEW)
```javascript
// Applied automatically in app.js:
// - General API: 100 req/15min per IP
// - Auth endpoints: 5 req/5min (brute force protection)
// - UPC lookup: 10 req/min (expensive API)

// Returns 429 with:
// { error: "Too many requests...", retryAfter: 900 }
```

## Implementation Checklist

When adding new feature:
- [ ] Identify which service layer function to create/modify
- [ ] Read existing similar routes and services
- [ ] Check schema in `db/schema.sql`
- [ ] Implement business logic in `src/services/<resource>Service.js`
- [ ] Implement route in `src/routes/<resource>.js` (HTTP layer only)
- [ ] Add JWT auth middleware
- [ ] Scope queries by `household_id`
- [ ] Check premium limits if adding data
- [ ] Add Winston logging for important events
- [ ] Handle errors with try/catch
- [ ] Write Jest tests in `tests/<feature>.test.js`
- [ ] Ensure all 84 tests still pass (100% pass rate required)
- [ ] Test locally before deployment

## Common Patterns

### Multi-tenancy (Household Scoping)
```javascript
// ✅ ALWAYS filter by household_id
const items = db.prepare(`
    SELECT * FROM inventory 
    WHERE household_id = ?
`).all(req.user.householdId);

// ❌ NEVER query without household_id (security issue)
const items = db.prepare('SELECT * FROM inventory').all();
```

### Error Responses
```javascript
try {
    // Business logic
    res.json({ success: true });
} catch (error) {
    console.error('Endpoint error:', error);
    res.status(500).json({ error: 'User-friendly message' });
}
```

### Sync Support
```javascript
const { logSync } = require('../services/syncLogger');

// Log changes for offline sync
logSync(householdId, 'inventory', itemId, 'CREATE', JSON.stringify(item));
```

## Key Files
- **Routes:** `src/routes/inventory.js`, `src/routes/grocery.js`, `src/routes/auth.js`
- **Database:** `src/models/database.js`, `db/schema.sql`
- **Auth:** `src/middleware/auth.js`
- **Premium:** `src/utils/premiumHelper.js`
- **Tests:** `tests/inventory.test.js`

## Gotchas
- ❌ Don't use async/await for SQLite (it's synchronous)
- ❌ Don't skip household_id filtering (security issue)
- ❌ Don't forget premium limit checks
- ✅ Always use prepared statements
- ✅ Always log sync events
- ✅ Always write tests
