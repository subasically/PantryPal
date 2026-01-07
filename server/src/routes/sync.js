const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const authenticateToken = require('../middleware/auth');

const router = express.Router();

router.use(authenticateToken);

// Get changes since last sync
router.get('/changes', (req, res) => {
    try {
        const householdId = req.user.householdId;
        const since = req.query.since; // ISO timestamp
        
        console.log(`[Sync] Changes requested by user ${req.user.id} (Household: ${householdId}) since ${since || 'beginning'}`);

        let query = `
            SELECT * FROM sync_log 
            WHERE household_id = ?
        `;
        const params = [householdId];

        if (since) {
            // Convert ISO timestamp to SQLite format for comparison
            // Replace 'T' with space and remove 'Z' suffix
            const sqliteTimestamp = since.replace('T', ' ').replace('Z', '').replace(/\.\d+$/, '');
            query += ' AND server_timestamp > ?';
            params.push(sqliteTimestamp);
        }

        query += ' ORDER BY server_timestamp ASC';

        const changes = db.prepare(query).all(...params);
        
        console.log(`[Sync] Returning ${changes.length} changes`);
        
        res.json({
            changes,
            serverTime: new Date().toISOString()
        });
    } catch (error) {
        console.error('Get changes error:', error);
        res.status(500).json({ error: 'Failed to get changes' });
    }
});

// Push local changes to server
router.post('/push', (req, res) => {
    try {
        const { changes } = req.body;
        const householdId = req.user.householdId;
        
        console.log(`[Sync] Push received from user ${req.user.id} (Household: ${householdId}) with ${changes?.length || 0} changes`);

        if (!Array.isArray(changes)) {
            return res.status(400).json({ error: 'Changes must be an array' });
        }

        const results = [];
        const insertLog = db.prepare(`
            INSERT INTO sync_log (id, household_id, entity_type, entity_id, action, payload, client_timestamp, synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1)
        `);

        for (const change of changes) {
            const { entityType, entityId, action, payload, clientTimestamp } = change;
            
            console.log(`[Sync] Processing change: ${entityType} ${entityId} (${action})`);

            try {
                // Apply the change
                applyChange(householdId, entityType, entityId, action, payload);

                // Log the sync
                const logId = uuidv4();
                insertLog.run(
                    logId,
                    householdId,
                    entityType,
                    entityId,
                    action,
                    JSON.stringify(payload),
                    clientTimestamp
                );

                results.push({ entityId, success: true });
            } catch (err) {
                console.error('Failed to apply change:', err);
                results.push({ entityId, success: false, error: err.message });
            }
        }

        res.json({
            results,
            serverTime: new Date().toISOString()
        });
    } catch (error) {
        console.error('Push changes error:', error);
        res.status(500).json({ error: 'Failed to push changes' });
    }
});

// Full sync - get complete inventory state
router.get('/full', (req, res) => {
    try {
        const householdId = req.user.householdId;
        console.log(`[Sync] Full sync requested by user ${req.user.id} (Household: ${householdId})`);

        const products = db.prepare(`
            SELECT * FROM products 
            WHERE household_id IS NULL OR household_id = ?
        `).all(householdId);

        const inventory = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand, 
                   p.upc as product_upc, p.image_url as product_image_url,
                   p.category as product_category,
                   l.name as location_name
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.household_id = ?
        `).all(householdId);
        
        console.log(`[Sync] Returning ${inventory.length} inventory items and ${products.length} products`);

        res.json({
            products,
            inventory,
            serverTime: new Date().toISOString()
        });
    } catch (error) {
        console.error('Full sync error:', error);
        res.status(500).json({ error: 'Failed to perform full sync' });
    }
});

function applyChange(householdId, entityType, entityId, action, payload) {
    switch (entityType) {
        case 'inventory':
            applyInventoryChange(householdId, entityId, action, payload);
            break;
        case 'product':
            applyProductChange(householdId, entityId, action, payload);
            break;
        default:
            throw new Error(`Unknown entity type: ${entityType}`);
    }
}

function applyInventoryChange(householdId, entityId, action, payload) {
    switch (action) {
        case 'create':
            db.prepare(`
                INSERT OR REPLACE INTO inventory (id, product_id, household_id, location_id, quantity, expiration_date, notes, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            `).run(entityId, payload.productId, householdId, payload.locationId || null, payload.quantity, payload.expirationDate, payload.notes);
            break;
        case 'update':
            db.prepare(`
                UPDATE inventory 
                SET quantity = ?, expiration_date = ?, notes = ?, location_id = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND household_id = ?
            `).run(payload.quantity, payload.expirationDate, payload.notes, payload.locationId || null, entityId, householdId);
            break;
        case 'delete':
            db.prepare('DELETE FROM inventory WHERE id = ? AND household_id = ?').run(entityId, householdId);
            break;
        default:
            throw new Error(`Unknown action: ${action}`);
    }
}

function applyProductChange(householdId, entityId, action, payload) {
    switch (action) {
        case 'create':
            db.prepare(`
                INSERT OR REPLACE INTO products (id, upc, name, brand, description, category, is_custom, household_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, ?, CURRENT_TIMESTAMP)
            `).run(entityId, payload.upc, payload.name, payload.brand, payload.description, payload.category, householdId);
            break;
        case 'update':
            db.prepare(`
                UPDATE products 
                SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND household_id = ?
            `).run(payload.name, payload.brand, payload.description, payload.category, entityId, householdId);
            break;
        case 'delete':
            db.prepare('DELETE FROM products WHERE id = ? AND household_id = ?').run(entityId, householdId);
            break;
        default:
            throw new Error(`Unknown action: ${action}`);
    }
}

module.exports = router;
