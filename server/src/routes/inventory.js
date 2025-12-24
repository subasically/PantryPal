const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const { authenticateToken } = require('../middleware/auth');

const router = express.Router();

// All routes require authentication
router.use(authenticateToken);

// Get all inventory items for household
router.get('/', (req, res) => {
    try {
        const householdId = req.user.householdId;
        const items = db.prepare(`
            SELECT 
                i.*,
                p.name as product_name,
                p.brand as product_brand,
                p.upc as product_upc,
                p.image_url as product_image_url,
                p.category as product_category,
                l.name as location_name,
                l.id as location_id
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.household_id = ?
            ORDER BY i.expiration_date ASC NULLS LAST, p.name ASC
        `).all(householdId);
        
        res.json(items);
    } catch (error) {
        console.error('Get inventory error:', error);
        res.status(500).json({ error: 'Failed to get inventory' });
    }
});

// Get expiring items (within N days)
router.get('/expiring', (req, res) => {
    try {
        const householdId = req.user.householdId;
        const days = parseInt(req.query.days) || 7;
        
        const items = db.prepare(`
            SELECT 
                i.*,
                p.name as product_name,
                p.brand as product_brand,
                p.upc as product_upc,
                p.image_url as product_image_url
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            WHERE i.household_id = ?
            AND i.expiration_date IS NOT NULL
            AND i.expiration_date <= date('now', '+' || ? || ' days')
            AND i.expiration_date >= date('now')
            ORDER BY i.expiration_date ASC
        `).all(householdId, days);
        
        res.json(items);
    } catch (error) {
        console.error('Get expiring items error:', error);
        res.status(500).json({ error: 'Failed to get expiring items' });
    }
});

// Get expired items
router.get('/expired', (req, res) => {
    try {
        const householdId = req.user.householdId;
        
        const items = db.prepare(`
            SELECT 
                i.*,
                p.name as product_name,
                p.brand as product_brand,
                p.upc as product_upc,
                p.image_url as product_image_url
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            WHERE i.household_id = ?
            AND i.expiration_date IS NOT NULL
            AND i.expiration_date < date('now')
            ORDER BY i.expiration_date ASC
        `).all(householdId);
        
        res.json(items);
    } catch (error) {
        console.error('Get expired items error:', error);
        res.status(500).json({ error: 'Failed to get expired items' });
    }
});

// Add item to inventory
router.post('/', (req, res) => {
    try {
        const { productId, quantity, expirationDate, notes, locationId } = req.body;
        const householdId = req.user.householdId;

        if (!productId) {
            return res.status(400).json({ error: 'Product ID is required' });
        }

        if (!locationId) {
            return res.status(400).json({ error: 'Location is required' });
        }

        // Verify product exists
        const product = db.prepare('SELECT id FROM products WHERE id = ?').get(productId);
        if (!product) {
            return res.status(404).json({ error: 'Product not found' });
        }

        // Verify location exists and belongs to household
        const location = db.prepare('SELECT id FROM locations WHERE id = ? AND household_id = ?').get(locationId, householdId);
        if (!location) {
            return res.status(404).json({ error: 'Location not found' });
        }

        // Check if already in inventory (same product, same expiration, same location)
        let existingItem = null;
        if (expirationDate) {
            existingItem = db.prepare(`
                SELECT * FROM inventory 
                WHERE product_id = ? AND household_id = ? AND expiration_date = ? AND location_id = ?
            `).get(productId, householdId, expirationDate, locationId);
        } else {
            existingItem = db.prepare(`
                SELECT * FROM inventory 
                WHERE product_id = ? AND household_id = ? AND expiration_date IS NULL AND location_id = ?
            `).get(productId, householdId, locationId);
        }

        if (existingItem) {
            // Increment quantity
            db.prepare(`
                UPDATE inventory 
                SET quantity = quantity + ?, notes = COALESCE(?, notes), updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
            `).run(quantity || 1, notes, existingItem.id);
            
            const item = db.prepare(`
                SELECT 
                    i.*,
                    p.name as product_name,
                    p.brand as product_brand,
                    p.upc as product_upc,
                    p.image_url as product_image_url,
                    p.category as product_category,
                    l.name as location_name
                FROM inventory i
                JOIN products p ON i.product_id = p.id
                LEFT JOIN locations l ON i.location_id = l.id
                WHERE i.id = ?
            `).get(existingItem.id);
            
            return res.json(item);
        }

        const inventoryId = uuidv4();
        db.prepare(`
            INSERT INTO inventory (id, product_id, household_id, location_id, quantity, expiration_date, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(inventoryId, productId, householdId, locationId, quantity || 1, expirationDate || null, notes || null);

        const item = db.prepare(`
            SELECT 
                i.*,
                p.name as product_name,
                p.brand as product_brand,
                p.upc as product_upc,
                p.image_url as product_image_url,
                p.category as product_category,
                l.name as location_name
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.id = ?
        `).get(inventoryId);

        res.status(201).json(item);
    } catch (error) {
        console.error('Add inventory error:', error);
        res.status(500).json({ error: 'Failed to add item to inventory' });
    }
});

// Quick add by UPC (lookup + add in one call)
router.post('/quick-add', async (req, res) => {
    try {
        const { upc, quantity, expirationDate, locationId } = req.body;
        const householdId = req.user.householdId;

        if (!upc) {
            return res.status(400).json({ error: 'UPC is required' });
        }

        if (!locationId) {
            return res.status(400).json({ error: 'Location is required' });
        }

        // Verify location exists
        const location = db.prepare('SELECT id FROM locations WHERE id = ? AND household_id = ?').get(locationId, householdId);
        if (!location) {
            return res.status(404).json({ error: 'Location not found' });
        }

        // Find or create product
        let product = db.prepare(`
            SELECT * FROM products 
            WHERE upc = ? AND (household_id IS NULL OR household_id = ?)
        `).get(upc, householdId);

        if (!product) {
            // Try external lookup
            const { lookupUPC } = require('../services/upcLookup');
            const lookupResult = await lookupUPC(upc);
            
            if (lookupResult.found) {
                const productId = uuidv4();
                db.prepare(`
                    INSERT INTO products (id, upc, name, brand, description, image_url, category, is_custom, household_id)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, NULL)
                `).run(
                    productId,
                    lookupResult.upc,
                    lookupResult.name,
                    lookupResult.brand,
                    lookupResult.description,
                    lookupResult.image_url,
                    lookupResult.category
                );
                product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
            } else {
                return res.status(404).json({ 
                    error: 'Product not found', 
                    upc,
                    requiresCustomProduct: true 
                });
            }
        }

        // Check if already in inventory (same product, same household, same location, same expiration)
        let existingItem = null;
        if (expirationDate) {
            existingItem = db.prepare(`
                SELECT * FROM inventory 
                WHERE product_id = ? AND household_id = ? AND expiration_date = ? AND location_id = ?
            `).get(product.id, householdId, expirationDate, locationId);
        } else {
            existingItem = db.prepare(`
                SELECT * FROM inventory 
                WHERE product_id = ? AND household_id = ? AND expiration_date IS NULL AND location_id = ?
            `).get(product.id, householdId, locationId);
        }

        if (existingItem) {
            // Increment quantity
            db.prepare(`
                UPDATE inventory 
                SET quantity = quantity + ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ?
            `).run(quantity || 1, existingItem.id);
            
            const item = db.prepare(`
                SELECT i.*, p.name as product_name, p.brand as product_brand, 
                       p.upc as product_upc, p.image_url as product_image_url,
                       l.name as location_name
                FROM inventory i
                JOIN products p ON i.product_id = p.id
                LEFT JOIN locations l ON i.location_id = l.id
                WHERE i.id = ?
            `).get(existingItem.id);
            
            return res.json({ item, action: 'updated' });
        }

        // Create new inventory entry
        const inventoryId = uuidv4();
        db.prepare(`
            INSERT INTO inventory (id, product_id, household_id, location_id, quantity, expiration_date)
            VALUES (?, ?, ?, ?, ?, ?)
        `).run(inventoryId, product.id, householdId, locationId, quantity || 1, expirationDate || null);

        const item = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand, 
                   p.upc as product_upc, p.image_url as product_image_url,
                   l.name as location_name
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.id = ?
        `).get(inventoryId);

        res.status(201).json({ item, action: 'created' });
    } catch (error) {
        console.error('Quick add error:', error);
        res.status(500).json({ error: 'Failed to quick add item' });
    }
});

// Update inventory item
router.put('/:id', (req, res) => {
    try {
        const { quantity, expirationDate, notes, locationId } = req.body;
        const householdId = req.user.householdId;

        const item = db.prepare('SELECT * FROM inventory WHERE id = ? AND household_id = ?')
            .get(req.params.id, householdId);
        
        if (!item) {
            return res.status(404).json({ error: 'Inventory item not found' });
        }

        // Verify location if provided
        if (locationId) {
            const location = db.prepare('SELECT id FROM locations WHERE id = ? AND household_id = ?').get(locationId, householdId);
            if (!location) {
                return res.status(404).json({ error: 'Location not found' });
            }
        }

        db.prepare(`
            UPDATE inventory 
            SET quantity = ?, expiration_date = ?, notes = ?, location_id = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        `).run(
            quantity !== undefined ? quantity : item.quantity,
            expirationDate !== undefined ? expirationDate : item.expiration_date,
            notes !== undefined ? notes : item.notes,
            locationId !== undefined ? locationId : item.location_id,
            req.params.id
        );

        const updated = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand, 
                   p.upc as product_upc, p.image_url as product_image_url,
                   l.name as location_name
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.id = ?
        `).get(req.params.id);

        res.json(updated);
    } catch (error) {
        console.error('Update inventory error:', error);
        res.status(500).json({ error: 'Failed to update inventory item' });
    }
});

// Adjust quantity (increment/decrement)
router.patch('/:id/quantity', (req, res) => {
    try {
        const { adjustment } = req.body; // positive or negative number
        const householdId = req.user.householdId;

        if (typeof adjustment !== 'number') {
            return res.status(400).json({ error: 'Adjustment must be a number' });
        }

        const item = db.prepare('SELECT * FROM inventory WHERE id = ? AND household_id = ?')
            .get(req.params.id, householdId);
        
        if (!item) {
            return res.status(404).json({ error: 'Inventory item not found' });
        }

        const newQuantity = item.quantity + adjustment;
        
        if (newQuantity <= 0) {
            // Remove item if quantity reaches 0
            db.prepare('DELETE FROM inventory WHERE id = ?').run(req.params.id);
            return res.json({ deleted: true, id: req.params.id });
        }

        db.prepare(`
            UPDATE inventory 
            SET quantity = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        `).run(newQuantity, req.params.id);

        const updated = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand, 
                   p.upc as product_upc, p.image_url as product_image_url
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            WHERE i.id = ?
        `).get(req.params.id);

        res.json(updated);
    } catch (error) {
        console.error('Adjust quantity error:', error);
        res.status(500).json({ error: 'Failed to adjust quantity' });
    }
});

// Delete inventory item
router.delete('/:id', (req, res) => {
    try {
        const householdId = req.user.householdId;
        
        const item = db.prepare('SELECT * FROM inventory WHERE id = ? AND household_id = ?')
            .get(req.params.id, householdId);
        
        if (!item) {
            return res.status(404).json({ error: 'Inventory item not found' });
        }

        db.prepare('DELETE FROM inventory WHERE id = ?').run(req.params.id);
        res.json({ success: true });
    } catch (error) {
        console.error('Delete inventory error:', error);
        res.status(500).json({ error: 'Failed to delete inventory item' });
    }
});

module.exports = router;
