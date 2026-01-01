const express = require('express');
const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const authenticateToken = require('../middleware/auth');
const { lookupUPC } = require('../services/upcLookup');
const { logSync } = require('../services/syncLogger');

const router = express.Router();

// All routes require authentication
router.use(authenticateToken);

// Lookup product by UPC
router.get('/lookup/:upc', async (req, res) => {
    try {
        const { upc } = req.params;
        
        // Check local database first
        let product = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc);
        
        if (product) {
            return res.json({ found: true, product, source: 'local' });
        }
        
        // Lookup from external API
        const lookupResult = await lookupUPC(upc);
        
        if (lookupResult.found) {
            // Cache the product (only if not already cached)
            const existingProduct = db.prepare('SELECT * FROM products WHERE upc = ?').get(lookupResult.upc);
            
            if (!existingProduct) {
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
                product = existingProduct;
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

        // If UPC provided, check if product exists
        if (upc) {
            const existing = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc);
            if (existing) {
                // Update existing product
                db.prepare(`
                    UPDATE products 
                    SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
                    WHERE upc = ?
                `).run(name, brand, description, category, upc);
                
                const product = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc);
                
                // Log sync event
                logSync(householdId, 'product', 'update', product.id, {
                    upc,
                    name,
                    brand,
                    description,
                    category
                });
                
                return res.json(product);
            }
        }

        const id = uuidv4();
        const finalUpc = upc || `CUSTOM-${Date.now()}`;

        db.prepare(`
            INSERT INTO products (id, upc, name, brand, description, category, is_custom, household_id)
            VALUES (?, ?, ?, ?, ?, ?, 1, ?)
        `).run(id, finalUpc, name, brand, description, category, householdId);

        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
        
        // Log sync event
        logSync(householdId, 'product', 'create', id, {
            upc: finalUpc,
            name,
            brand,
            description,
            category,
            is_custom: 1
        });

        res.status(201).json(product);
    } catch (error) {
        console.error('Create product error:', error);
        res.status(500).json({ error: 'Failed to create product' });
    }
});

// Get all products for household
router.get('/', (req, res) => {
    try {
        const householdId = req.user.householdId;
        
        const products = db.prepare(`
            SELECT * FROM products 
            WHERE household_id = ? OR household_id IS NULL
            ORDER BY created_at DESC
        `).all(householdId);
        
        res.json(products);
    } catch (error) {
        console.error('Get products error:', error);
        res.status(500).json({ error: 'Failed to get products' });
    }
});

// Get single product by ID
router.get('/:id', (req, res) => {
    try {
        const { id } = req.params;
        
        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
        
        if (!product) {
            return res.status(404).json({ error: 'Product not found' });
        }
        
        res.json(product);
    } catch (error) {
        console.error('Get product error:', error);
        res.status(500).json({ error: 'Failed to get product' });
    }
});

// Update product
router.put('/:id', (req, res) => {
    try {
        const { id } = req.params;
        const { name, brand, description, category } = req.body;
        const householdId = req.user.householdId;
        
        // Check if product exists
        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
        if (!product) {
            return res.status(404).json({ error: 'Product not found' });
        }
        
        // Update product
        db.prepare(`
            UPDATE products 
            SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        `).run(name, brand, description, category, id);
        
        const updatedProduct = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
        
        // Log sync event
        logSync(householdId, 'product', 'update', id, {
            name,
            brand,
            description,
            category
        });
        
        res.json(updatedProduct);
    } catch (error) {
        console.error('Update product error:', error);
        res.status(500).json({ error: 'Failed to update product' });
    }
});

// Delete product
router.delete('/:id', (req, res) => {
    try {
        const { id } = req.params;
        const householdId = req.user.householdId;
        
        // Check if product exists
        const product = db.prepare('SELECT * FROM products WHERE id = ?').get(id);
        if (!product) {
            return res.status(404).json({ error: 'Product not found' });
        }
        
        // Check if product is in inventory
        const inventoryCount = db.prepare('SELECT COUNT(*) as count FROM inventory WHERE product_id = ?').get(id);
        if (inventoryCount.count > 0) {
            return res.status(400).json({ error: 'Cannot delete product that is in inventory' });
        }
        
        // Delete product
        db.prepare('DELETE FROM products WHERE id = ?').run(id);
        
        // Log sync event
        logSync(householdId, 'product', 'delete', id, {});
        
        res.json({ success: true });
    } catch (error) {
        console.error('Delete product error:', error);
        res.status(500).json({ error: 'Failed to delete product' });
    }
});

module.exports = router;
