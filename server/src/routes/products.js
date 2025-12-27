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

module.exports = router;
