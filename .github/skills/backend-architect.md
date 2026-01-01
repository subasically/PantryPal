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
- **Testing:** Jest + Supertest
- **Production:** Docker Compose on VPS (62.146.177.62)

## Quick Reference

### Project Structure
```
server/
├── src/
│   ├── app.js              # Express app factory
│   ├── routes/             # REST endpoints (resource-based)
│   ├── models/database.js  # SQLite connection
│   ├── services/           # External integrations
│   ├── middleware/auth.js  # JWT authentication
│   └── utils/premiumHelper.js # Freemium logic
└── db/schema.sql           # Database schema
```

### Route Pattern (Controller)
```javascript
const express = require('express');
const db = require('../models/database');
const authenticateToken = require('../middleware/auth');
const router = express.Router();

router.use(authenticateToken);

router.get('/', (req, res) => {
    try {
        const householdId = req.user.householdId;
        const items = db.prepare('SELECT * FROM table WHERE household_id = ?').all(householdId);
        res.json(items);
    } catch (error) {
        console.error('Error:', error);
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

## Implementation Checklist

When adding new feature:
- [ ] Read existing similar routes
- [ ] Check schema in `db/schema.sql`
- [ ] Implement route in `src/routes/<resource>.js`
- [ ] Add JWT auth middleware
- [ ] Scope queries by `household_id`
- [ ] Check premium limits if adding data
- [ ] Handle errors with try/catch
- [ ] Write Jest tests in `tests/<feature>.test.js`
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
