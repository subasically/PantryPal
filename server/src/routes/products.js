const express = require('express');
const authenticateToken = require('../middleware/auth');
const productService = require('../services/productService');

const router = express.Router();

// All routes require authentication
router.use(authenticateToken);

// Lookup product by UPC
router.get('/lookup/:upc', async (req, res) => {
    try {
        const { upc } = req.params;
        console.log(`🔍 [Products] UPC lookup request: ${upc}`);
        console.log(`   - User ID: ${req.user.id}`);
        console.log(`   - Household ID: ${req.user.householdId}`);

        const result = await productService.lookupProductByUPC(upc, req.user.householdId);

        console.log(`✅ [Products] UPC lookup result for ${upc}:`);
        console.log(`   - Product found: ${result.product !== null}`);
        if (result.product) {
            console.log(`   - Product ID: ${result.product.id}`);
            console.log(`   - Product name: ${result.product.name}`);
            console.log(`   - Product brand: ${result.product.brand || 'null'}`);
        }

        res.json(result);
    } catch (error) {
        console.error('❌ [Products] UPC lookup error:', error);
        res.status(500).json({ error: 'UPC lookup failed' });
    }
});

// Create custom product
router.post('/', (req, res) => {
    try {
        const { upc, name, brand, description, category } = req.body;
        const result = productService.createCustomProduct(req.user.householdId, {
            upc,
            name,
            brand,
            description,
            category
        });
        const status = result.wasUpdated ? 200 : 201;
        res.status(status).json(result.product);
    } catch (error) {
        console.error('Create product error:', error);
        if (error.message === 'Product name is required') {
            return res.status(400).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to create product' });
    }
});

// Get all products for household
router.get('/', (req, res) => {
    try {
        const products = productService.getAllProducts(req.user.householdId);
        res.json(products);
    } catch (error) {
        console.error('Get products error:', error);
        res.status(500).json({ error: 'Failed to get products' });
    }
});

// Get single product by ID
router.get('/:id', (req, res) => {
    try {
        const product = productService.getProductById(req.params.id);
        res.json(product);
    } catch (error) {
        console.error('Get product error:', error);
        if (error.message === 'Product not found') {
            return res.status(404).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to get product' });
    }
});

// Update product
router.put('/:id', (req, res) => {
    try {
        const { name, brand, description, category } = req.body;
        const updatedProduct = productService.updateProduct(req.user.householdId, req.params.id, {
            name,
            brand,
            description,
            category
        });
        res.json(updatedProduct);
    } catch (error) {
        console.error('Update product error:', error);
        if (error.message === 'Product not found') {
            return res.status(404).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to update product' });
    }
});

// Delete product
router.delete('/:id', (req, res) => {
    try {
        productService.deleteProduct(req.user.householdId, req.params.id);
        res.json({ success: true });
    } catch (error) {
        console.error('Delete product error:', error);
        if (error.message === 'Product not found') {
            return res.status(404).json({ error: error.message });
        }
        if (error.message === 'Cannot delete product that is in inventory') {
            return res.status(400).json({ error: error.message });
        }
        res.status(500).json({ error: 'Failed to delete product' });
    }
});

module.exports = router;
