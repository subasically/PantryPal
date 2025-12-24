const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const { authenticateToken } = require('../middleware/auth');
const { lookupUPC } = require('../services/upcLookup');

const router = express.Router();

// All routes require authentication
router.use(authenticateToken);

// Lookup UPC (checks local cache first, then external API)
router.get('/lookup/:upc', async (req, res) => {
    try {
        const { upc } = req.params;
        const householdId = req.user.householdId;

        // Check for household-specific custom product first (with custom UPC format)
        const customUpc = `${upc}-${householdId}`;
        let product = db.prepare(`
            SELECT * FROM products WHERE upc = ?
        `).get(customUpc);

        if (product && product.name) {
            // Return household's custom override, but with original UPC for display
            return res.json({ found: true, product: { ...product, original_upc: upc }, source: 'custom' });
        }

        // Check local cache (global products + household custom products with original UPC)
        product = db.prepare(`
            SELECT * FROM products 
            WHERE upc = ? AND (household_id IS NULL OR household_id = ?)
        `).get(upc, householdId);

        // If cached product has a valid name, return it
        if (product && product.name && product.name !== 'Unknown Product') {
            return res.json({ found: true, product, source: 'cache' });
        }

        // Lookup from external API
        const lookupResult = await lookupUPC(upc);
        
        if (lookupResult.found) {
            // Cache the product (only if not already cached)
            if (!product) {
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
            }
            return res.json({ found: true, product, source: 'api' });
        }

        res.json({ found: false, upc });
    } catch (error) {
        console.error('UPC lookup error:', error);
        res.status(500).json({ error: 'UPC lookup failed' });
    }
});

// Create custom product
router.post('/', (req, res) => {
    try {
        const { upc, name, brand, description, category } = req.body;
        const householdId = req.user.householdId;

        if (!name) {
            return res.status(400).json({ error: 'Product name is required' });
        }

        // Check if UPC already exists - update if it does
        if (upc) {
            const existing = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc);
            if (existing) {
                // Update the existing product with new name/brand if it's a custom product for this household
                if (existing.is_custom && existing.household_id === householdId) {
                    db.prepare(`
                        UPDATE products 
                        SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
                        WHERE upc = ?
                    `).run(name, brand || existing.brand, description || existing.description, category || existing.category, upc);
                    
                    const updated = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc);
                    return res.json(updated);
                } else {
                    // For non-custom products or other household's custom products, 
                    // create a household-specific custom product with modified UPC
                    const customUpc = `${upc}-${householdId}`;
                    const existingCustom = db.prepare('SELECT * FROM products WHERE upc = ?').get(customUpc);
                    
                    if (existingCustom) {
                        // Update existing household override
                        db.prepare(`
                            UPDATE products 
                            SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
                            WHERE upc = ?
                        `).run(name, brand || existingCustom.brand, description || existingCustom.description, category || existingCustom.category, customUpc);
                        
                        const updated = db.prepare('SELECT * FROM products WHERE upc = ?').get(customUpc);
                        return res.json(updated);
                    }
                    
                    const productId = uuidv4();
                    db.prepare(`
                        INSERT INTO products (id, upc, name, brand, description, category, is_custom, household_id)
                        VALUES (?, ?, ?, ?, ?, ?, 1, ?)
                    `).run(productId, customUpc, name, brand || existing.brand, description || existing.description, category || existing.category, householdId);
                    
                    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
                    return res.status(201).json(product);
                }
            }
        }

        const productId = uuidv4();
        db.prepare(`
            INSERT INTO products (id, upc, name, brand, description, category, is_custom, household_id)
            VALUES (?, ?, ?, ?, ?, ?, 1, ?)
        `).run(productId, upc || null, name, brand || null, description || null, category || null, householdId);

        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
        res.status(201).json(product);
    } catch (error) {
        console.error('Create product error:', error);
        res.status(500).json({ error: 'Failed to create product' });
    }
});

// Get all products (global + household custom)
router.get('/', (req, res) => {
    try {
        const householdId = req.user.householdId;
        const products = db.prepare(`
            SELECT * FROM products 
            WHERE household_id IS NULL OR household_id = ?
            ORDER BY name
        `).all(householdId);
        
        res.json(products);
    } catch (error) {
        console.error('Get products error:', error);
        res.status(500).json({ error: 'Failed to get products' });
    }
});

// Get single product
router.get('/:id', (req, res) => {
    try {
        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
        if (!product) {
            return res.status(404).json({ error: 'Product not found' });
        }
        res.json(product);
    } catch (error) {
        console.error('Get product error:', error);
        res.status(500).json({ error: 'Failed to get product' });
    }
});

// Update custom product
router.put('/:id', (req, res) => {
    try {
        const { name, brand, description, category } = req.body;
        const householdId = req.user.householdId;

        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
        if (!product) {
            return res.status(404).json({ error: 'Product not found' });
        }

        // Only allow editing custom products owned by household
        if (!product.is_custom || product.household_id !== householdId) {
            return res.status(403).json({ error: 'Cannot edit this product' });
        }

        db.prepare(`
            UPDATE products 
            SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        `).run(name || product.name, brand, description, category, req.params.id);

        const updated = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
        res.json(updated);
    } catch (error) {
        console.error('Update product error:', error);
        res.status(500).json({ error: 'Failed to update product' });
    }
});

// Delete custom product
router.delete('/:id', (req, res) => {
    try {
        const householdId = req.user.householdId;
        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(req.params.id);
        
        if (!product) {
            return res.status(404).json({ error: 'Product not found' });
        }

        if (!product.is_custom || product.household_id !== householdId) {
            return res.status(403).json({ error: 'Cannot delete this product' });
        }

        // Check if product is in inventory
        const inInventory = db.prepare('SELECT id FROM inventory WHERE product_id = ?').get(req.params.id);
        if (inInventory) {
            return res.status(400).json({ error: 'Cannot delete product that is in inventory' });
        }

        db.prepare('DELETE FROM products WHERE id = ?').run(req.params.id);
        res.json({ success: true });
    } catch (error) {
        console.error('Delete product error:', error);
        res.status(500).json({ error: 'Failed to delete product' });
    }
});

module.exports = router;
