const express = require('express');
const authenticateToken = require('../middleware/auth');
const inventoryService = require('../services/inventoryService');
const productService = require('../services/productService');

const router = express.Router();

router.use(authenticateToken);

// Get all inventory items for household
router.get('/', (req, res) => {
    try {
        const inventory = inventoryService.getAllInventory(req.user.householdId);
        res.json(inventory);
    } catch (error) {
        console.error('Get inventory error:', error);
        res.status(500).json({ error: 'Failed to get inventory' });
    }
});

// Get expiring items
router.get('/expiring', (req, res) => {
    try {
        const days = parseInt(req.query.days) || 7;
        const inventory = inventoryService.getExpiringItems(req.user.householdId, days);
        res.json(inventory);
    } catch (error) {
        console.error('Get expiring items error:', error);
        res.status(500).json({ error: 'Failed to get expiring items' });
    }
});

// Get expired items
router.get('/expired', (req, res) => {
    try {
        const inventory = inventoryService.getExpiredItems(req.user.householdId);
        res.json(inventory);
    } catch (error) {
        console.error('Get expired items error:', error);
        res.status(500).json({ error: 'Failed to get expired items' });
    }
});

// Add item to inventory
router.post('/', (req, res) => {
    try {
        const { productId, quantity, expirationDate, notes, locationId } = req.body;
        const item = inventoryService.addInventoryItem(req.user.householdId, {
            productId,
            quantity,
            expirationDate,
            notes,
            locationId
        });
        // Return 200 if item was updated, 201 if created
        const status = item._wasUpdated ? 200 : 201;
        delete item._wasUpdated; // Remove internal flag before returning
        res.status(status).json(item);
    } catch (error) {
        console.error('Add inventory error:', error);
        if (error.code === 'PREMIUM_REQUIRED' || error.code === 'LIMIT_REACHED') {
            return res.status(403).json({ 
                error: error.message,
                code: error.code,
                limit: error.limit,
                upgradeRequired: true
            });
        }
        if (error.code === 'LOCATION_REQUIRED') {
            return res.status(400).json({ 
                error: error.message,
                code: error.code
            });
        }
        if (error.message === 'Product ID is required') {
            return res.status(400).json({ error: error.message });
        }
        if (error.message === 'Product not found' || error.message.includes('Location')) {
            return res.status(404).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to add item to inventory' });
    }
});

// Quick add by UPC (lookup + add in one call)
router.post('/quick-add', async (req, res) => {
    try {
        const { upc, quantity, expirationDate, locationId } = req.body;
        const result = await inventoryService.quickAddByUPC(req.user.householdId, {
            upc,
            quantity,
            expirationDate,
            locationId
        });
        res.status(201).json(result);
    } catch (error) {
        console.error('Quick add error:', error);
        if (error.code === 'PREMIUM_REQUIRED' || error.code === 'LIMIT_REACHED') {
            return res.status(403).json({ 
                error: error.message,
                code: error.code,
                limit: error.limit,
                upgradeRequired: true
            });
        }
        if (error.code === 'LOCATION_REQUIRED') {
            return res.status(400).json({ 
                error: error.message,
                code: error.code
            });
        }
        if (error.requiresCustomProduct) {
            return res.status(404).json({ 
                error: error.message,
                upc: error.upc,
                requiresCustomProduct: true
            });
        }
        if (error.message.includes('not found')) {
            return res.status(404).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to quick add item' });
    }
});

// Update inventory item
router.put('/:id', (req, res) => {
    try {
        const { quantity, expirationDate, notes, locationId } = req.body;
        const updated = inventoryService.updateInventoryItem(req.user.householdId, req.params.id, {
            quantity,
            expirationDate,
            notes,
            locationId
        });
        res.json(updated);
    } catch (error) {
        console.error('Update inventory error:', error);
        if (error.code === 'PREMIUM_REQUIRED') {
            return res.status(403).json({ 
                error: error.message,
                code: error.code,
                upgradeRequired: true
            });
        }
        if (error.code === 'LOCATION_REQUIRED' || error.code === 'INVALID_LOCATION') {
            return res.status(400).json({ 
                error: error.message,
                code: error.code
            });
        }
        if (error.message === 'Inventory item not found') {
            return res.status(404).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to update inventory item' });
    }
});

// Adjust quantity (increment/decrement)
router.patch('/:id/quantity', (req, res) => {
    try {
        const { adjustment } = req.body;
        
        if (typeof adjustment !== 'number') {
            return res.status(400).json({ error: 'Adjustment must be a number' });
        }

        const result = inventoryService.adjustQuantity(req.user.householdId, req.params.id, adjustment);
        res.json(result);
    } catch (error) {
        console.error('Adjust quantity error:', error);
        if (error.code === 'PREMIUM_REQUIRED') {
            return res.status(403).json({ 
                error: error.message,
                code: error.code,
                upgradeRequired: true
            });
        }
        if (error.message === 'Inventory item not found') {
            return res.status(404).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to adjust quantity' });
    }
});

// Delete inventory item
router.delete('/:id', (req, res) => {
    try {
        inventoryService.deleteInventoryItem(req.user.householdId, req.params.id);
        res.json({ success: true });
    } catch (error) {
        console.error('Delete inventory error:', error);
        if (error.code === 'PREMIUM_REQUIRED') {
            return res.status(403).json({ 
                error: error.message,
                code: error.code,
                upgradeRequired: true
            });
        }
        if (error.message === 'Inventory item not found') {
            return res.status(404).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to delete inventory item' });
    }
});

module.exports = router;
