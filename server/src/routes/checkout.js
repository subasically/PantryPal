const express = require('express');
const router = express.Router();
const db = require('../models/database');
const { v4: uuidv4 } = require('uuid');
const authenticateToken = require('../middleware/auth');
const pushService = require('../services/pushNotifications');
const { logSync } = require('../services/syncLogger');

// All routes require authentication
router.use(authenticateToken);

// Checkout an item by UPC (quick scan mode - reduces quantity by 1)
router.post('/scan', (req, res) => {
    try {
        const { upc } = req.body;
        console.log(`[Checkout] Scan request - UPC: ${upc}, User: ${req.user.id}, Household: ${req.user.householdId}`);

        if (!upc) {
            return res.status(400).json({ error: 'UPC is required' });
        }

        // 1. Check for household-specific custom product first (with custom UPC format)
        const customUpc = `${upc}-${req.user.householdId}`;
        let product = db.prepare(`
            SELECT * FROM products WHERE upc = ?
        `).get(customUpc);

        // 2. If not found, check global products
        if (!product) {
            product = db.prepare(`
                SELECT * FROM products 
                WHERE upc = ? AND (household_id IS NULL OR household_id = ?)
            `).get(upc, req.user.householdId);
        }

        console.log(`[Checkout] Product lookup for UPC ${upc}:`, product ? `Found ${product.name} (ID: ${product.id})` : 'Not found');

        if (!product) {
            return res.status(200).json({ 
                success: false,
                error: 'Product not found',
                found: false,
                upc: upc
            });
        }

        // Find inventory item with this product (prefer oldest expiration)
        const inventoryItem = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            WHERE i.product_id = ? AND i.household_id = ? AND i.quantity > 0
            ORDER BY 
                CASE WHEN i.expiration_date IS NULL THEN 1 ELSE 0 END,
                i.expiration_date ASC
            LIMIT 1
        `).get(product.id, req.user.householdId);

        console.log(`[Checkout] Inventory lookup for product ${product.id}:`, inventoryItem ? `Found ${inventoryItem.quantity} in stock` : 'Not in inventory');

        if (!inventoryItem) {
            return res.status(200).json({ 
                success: false,
                error: 'Item not in inventory',
                found: true,
                inStock: false,
                product: {
                    id: product.id,
                    name: product.name,
                    brand: product.brand
                }
            });
        }

        const now = new Date().toISOString();
        const checkoutId = uuidv4();

        // Record checkout in history
        db.prepare(`
            INSERT INTO checkout_history (id, inventory_id, product_id, household_id, user_id, quantity, checked_out_at)
            VALUES (?, ?, ?, ?, ?, 1, ?)
        `).run(checkoutId, inventoryItem.id, product.id, req.user.householdId, req.user.id, now);

        // Reduce quantity or delete if last one
        if (inventoryItem.quantity <= 1) {
            db.prepare('DELETE FROM inventory WHERE id = ?').run(inventoryItem.id);
            
            logSync(req.user.householdId, 'inventory', inventoryItem.id, 'delete', {});
        } else {
            db.prepare('UPDATE inventory SET quantity = quantity - 1, updated_at = ? WHERE id = ?')
                .run(now, inventoryItem.id);
                
            logSync(req.user.householdId, 'inventory', inventoryItem.id, 'update', { 
                quantity: inventoryItem.quantity - 1,
                expirationDate: inventoryItem.expiration_date,
                notes: inventoryItem.notes,
                locationId: inventoryItem.location_id
            });
        }

        // Get updated inventory item (or null if deleted)
        const updatedItem = inventoryItem.quantity > 1 
            ? db.prepare(`
                SELECT i.*, p.name as product_name, p.brand as product_brand, p.image_url as product_image
                FROM inventory i
                JOIN products p ON i.product_id = p.id
                WHERE i.id = ?
            `).get(inventoryItem.id)
            : null;

        res.json({
            success: true,
            message: `Checked out 1x ${product.name}`,
            product: {
                id: product.id,
                name: product.name,
                brand: product.brand,
                imageUrl: product.image_url
            },
            previousQuantity: inventoryItem.quantity,
            newQuantity: inventoryItem.quantity - 1,
            itemDeleted: inventoryItem.quantity <= 1,
            inventoryItem: updatedItem,
            checkoutId: checkoutId
        });

        // Send push notification to household members (async, don't wait)
        const itemName = product.brand ? `${product.brand} ${product.name}` : product.name;
        pushService.sendCheckoutNotification(
            req.user.householdId,
            req.user.id,
            itemName,
            inventoryItem.quantity - 1
        ).catch(err => console.error('Failed to send checkout notification:', err));
    } catch (error) {
        console.error('Error during checkout scan:', error);
        res.status(500).json({ error: 'Failed to process checkout' });
    }
});

// Get checkout history
router.get('/history', (req, res) => {
    try {
        const { startDate, endDate, limit = 50, offset = 0 } = req.query;

        let query = `
            SELECT 
                ch.*,
                p.name as product_name,
                p.brand as product_brand,
                p.image_url as product_image,
                u.name as user_name
            FROM checkout_history ch
            JOIN products p ON ch.product_id = p.id
            JOIN users u ON ch.user_id = u.id
            WHERE ch.household_id = ?
        `;
        const params = [req.user.householdId];

        if (startDate) {
            query += ' AND ch.checked_out_at >= ?';
            params.push(startDate);
        }

        if (endDate) {
            query += ' AND ch.checked_out_at <= ?';
            params.push(endDate);
        }

        query += ' ORDER BY ch.checked_out_at DESC LIMIT ? OFFSET ?';
        params.push(parseInt(limit), parseInt(offset));

        const history = db.prepare(query).all(...params);

        // Get total count
        let countQuery = `
            SELECT COUNT(*) as total FROM checkout_history ch
            WHERE ch.household_id = ?
        `;
        const countParams = [req.user.householdId];

        if (startDate) {
            countQuery += ' AND ch.checked_out_at >= ?';
            countParams.push(startDate);
        }
        if (endDate) {
            countQuery += ' AND ch.checked_out_at <= ?';
            countParams.push(endDate);
        }

        const total = db.prepare(countQuery).get(...countParams);

        res.json({
            history: history,
            pagination: {
                total: total.total,
                limit: parseInt(limit),
                offset: parseInt(offset)
            }
        });
    } catch (error) {
        console.error('Error fetching checkout history:', error);
        res.status(500).json({ error: 'Failed to fetch checkout history' });
    }
});

// Get consumption stats (for future analytics)
router.get('/stats', (req, res) => {
    try {
        const { days = 30 } = req.query;
        const startDate = new Date();
        startDate.setDate(startDate.getDate() - parseInt(days));

        // Total items checked out
        const totalCheckouts = db.prepare(`
            SELECT COUNT(*) as total, SUM(quantity) as total_quantity
            FROM checkout_history
            WHERE household_id = ? AND checked_out_at >= ?
        `).get(req.user.householdId, startDate.toISOString());

        // Top consumed products
        const topProducts = db.prepare(`
            SELECT 
                p.id, p.name, p.brand,
                SUM(ch.quantity) as total_consumed
            FROM checkout_history ch
            JOIN products p ON ch.product_id = p.id
            WHERE ch.household_id = ? AND ch.checked_out_at >= ?
            GROUP BY p.id
            ORDER BY total_consumed DESC
            LIMIT 10
        `).all(req.user.householdId, startDate.toISOString());

        // Consumption by day
        const byDay = db.prepare(`
            SELECT 
                DATE(checked_out_at) as date,
                SUM(quantity) as total
            FROM checkout_history
            WHERE household_id = ? AND checked_out_at >= ?
            GROUP BY DATE(checked_out_at)
            ORDER BY date DESC
        `).all(req.user.householdId, startDate.toISOString());

        res.json({
            period: `Last ${days} days`,
            totalCheckouts: totalCheckouts.total || 0,
            totalQuantity: totalCheckouts.total_quantity || 0,
            topProducts: topProducts,
            byDay: byDay
        });
    } catch (error) {
        console.error('Error fetching checkout stats:', error);
        res.status(500).json({ error: 'Failed to fetch stats' });
    }
});

module.exports = router;
