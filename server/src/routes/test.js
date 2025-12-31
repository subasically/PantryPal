const express = require('express');
const { v4: uuidv4 } = require('uuid');
const bcrypt = require('bcryptjs');
const db = require('../models/database');

const router = express.Router();

// Test admin key - only for test environment
const TEST_ADMIN_KEY = process.env.TEST_ADMIN_KEY || 'test-admin-secret-change-me';

// Middleware to verify test mode and admin key
const requireTestMode = (req, res, next) => {
    // Only allow in test/development mode
    if (process.env.NODE_ENV === 'production' && process.env.ALLOW_TEST_ENDPOINTS !== 'true') {
        return res.status(404).json({ error: 'Not found' });
    }
    
    // Verify admin key
    const providedKey = req.headers['x-test-admin-key'];
    if (providedKey !== TEST_ADMIN_KEY) {
        return res.status(403).json({ error: 'Forbidden' });
    }
    
    next();
};

router.use(requireTestMode);

// Status endpoint - verify test endpoints are enabled
router.get('/status', (req, res) => {
    res.json({
        enabled: true,
        message: 'Test endpoints are active',
        timestamp: new Date().toISOString()
    });
});

// Reset database to clean state
router.post('/reset', (req, res) => {
    try {
        console.log('[Test] Resetting database...');
        
        // Delete all test data (keep schema)
        db.prepare('DELETE FROM checkout_history').run();
        db.prepare('DELETE FROM grocery_items').run();
        db.prepare('DELETE FROM inventory').run();
        db.prepare('DELETE FROM products WHERE household_id IS NOT NULL').run(); // Keep global products
        db.prepare('DELETE FROM locations').run();
        db.prepare('DELETE FROM households').run();
        db.prepare('DELETE FROM users').run();
        
        console.log('[Test] Database reset complete');
        
        res.json({
            success: true,
            message: 'Database reset successfully'
        });
    } catch (error) {
        console.error('[Test] Reset error:', error);
        res.status(500).json({ error: 'Failed to reset database' });
    }
});

// Seed database with test data
router.post('/seed', async (req, res) => {
    try {
        console.log('[Test] Seeding database...');
        
        // Create test household
        const householdId = uuidv4();
        
        db.prepare(`
            INSERT INTO households (id, name, is_premium, premium_expires_at, created_at)
            VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP)
        `).run(householdId, 'Test Household', 0, null);
        
        // Create test user
        const userId = uuidv4();
        const email = 'test@pantrypal.com';
        const password = 'Test123!';
        const hashedPassword = await bcrypt.hash(password, 10);
        
        db.prepare(`
            INSERT INTO users (id, email, password_hash, first_name, last_name, household_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(userId, email, hashedPassword, 'Test', 'User', householdId);
        
        // Create test locations
        const fridgeId = uuidv4();
        const pantryId = uuidv4();
        const freezerId = uuidv4();
        
        db.prepare(`
            INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(fridgeId, householdId, 'Fridge', null, 0, 0);
        
        db.prepare(`
            INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(pantryId, householdId, 'Pantry', null, 0, 1);
        
        db.prepare(`
            INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(freezerId, householdId, 'Freezer', null, 0, 2);
        
        // Create test products
        const milkProductId = uuidv4();
        const breadProductId = uuidv4();
        
        db.prepare(`
            INSERT INTO products (id, upc, name, brand, category, is_custom, household_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(milkProductId, 'TEST_MILK_001', 'Milk', 'Test Brand', 'Dairy', 0, null);
        
        db.prepare(`
            INSERT INTO products (id, upc, name, brand, category, is_custom, household_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(breadProductId, 'TEST_BREAD_001', 'Bread', 'Test Bakery', 'Bakery', 0, null);
        
        // Create test inventory items
        const milkItemId = uuidv4();
        const breadItemId = uuidv4();
        
        db.prepare(`
            INSERT INTO inventory (id, product_id, household_id, location_id, quantity, expiration_date, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(milkItemId, milkProductId, householdId, fridgeId, 2, '2025-02-01');
        
        db.prepare(`
            INSERT INTO inventory (id, product_id, household_id, location_id, quantity, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        `).run(breadItemId, breadProductId, householdId, pantryId, 1);
        
        console.log('[Test] Database seeded successfully');
        
        res.json({
            success: true,
            testUser: {
                email,
                password,
                userId,
                householdId
            },
            testData: {
                locations: { 
                    fridgeId, 
                    pantryId,
                    freezerId 
                },
                products: { 
                    milkProductId, 
                    breadProductId 
                },
                inventory: { 
                    milkItemId,
                    breadItemId 
                }
            }
        });
    } catch (error) {
        console.error('[Test] Seed error:', error);
        res.status(500).json({ error: 'Failed to seed database', details: error.message });
    }
});

// Get test user credentials (for tests to verify state)
router.get('/credentials', (req, res) => {
    res.json({
        email: 'test@pantrypal.com',
        password: 'Test123!'
    });
});

// Set premium status for test user
router.post('/premium/:householdId', (req, res) => {
    try {
        const { householdId } = req.params;
        const { isPremium } = req.body;
        
        const expiresAt = isPremium 
            ? new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString() // 1 year
            : null;
        
        db.prepare(`
            UPDATE households 
            SET is_premium = ?, premium_expires_at = ?
            WHERE id = ?
        `).run(isPremium ? 1 : 0, expiresAt, householdId);
        
        res.json({ success: true });
    } catch (error) {
        console.error('[Test] Premium update error:', error);
        res.status(500).json({ error: 'Failed to update premium status' });
    }
});

module.exports = router;
