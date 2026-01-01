const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const { lookupUPC } = require('./upcLookup');
const { logSync } = require('./syncLogger');

/**
 * Lookup product by UPC (local database first, then external API)
 * @param {string} upc - Product UPC
 * @returns {Object} { found, product, source }
 */
async function lookupProductByUPC(upc) {
    // Check local database first
    let product = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc);
    
    if (product) {
        return { found: true, product, source: 'local' };
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
        return { found: true, product, source: 'api' };
    }

    return { found: false, upc };
}

/**
 * Create custom product
 * @param {string} householdId - Household ID
 * @param {Object} productData - { upc, name, brand, description, category }
 * @returns {Object} { product, wasUpdated: boolean }
 */
function createCustomProduct(householdId, productData) {
    const { upc, name, brand, description, category } = productData;

    if (!name) {
        throw new Error('Product name is required');
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
            
            return { product, wasUpdated: true };
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

    return { product, wasUpdated: false };
}

/**
 * Get all products for household
 * @param {string} householdId - Household ID
 * @returns {Array} Array of products
 */
function getAllProducts(householdId) {
    const products = db.prepare(`
        SELECT * FROM products 
        WHERE household_id = ? OR household_id IS NULL
        ORDER BY created_at DESC
    `).all(householdId);
    
    return products;
}

/**
 * Get single product by ID
 * @param {string} productId - Product ID
 * @returns {Object} Product object
 */
function getProductById(productId) {
    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
    
    if (!product) {
        throw new Error('Product not found');
    }
    
    return product;
}

/**
 * Update product
 * @param {string} householdId - Household ID
 * @param {string} productId - Product ID
 * @param {Object} updates - { name, brand, description, category }
 * @returns {Object} Updated product
 */
function updateProduct(householdId, productId, updates) {
    const { name, brand, description, category } = updates;
    
    // Check if product exists
    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
    if (!product) {
        throw new Error('Product not found');
    }
    
    // Update product
    db.prepare(`
        UPDATE products 
        SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    `).run(name, brand, description, category, productId);
    
    const updatedProduct = db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
    
    // Log sync event
    logSync(householdId, 'product', 'update', productId, {
        name,
        brand,
        description,
        category
    });
    
    return updatedProduct;
}

/**
 * Delete product
 * @param {string} householdId - Household ID
 * @param {string} productId - Product ID
 */
function deleteProduct(householdId, productId) {
    // Check if product exists
    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId);
    if (!product) {
        throw new Error('Product not found');
    }
    
    // Check if product is in inventory
    const inventoryCount = db.prepare('SELECT COUNT(*) as count FROM inventory WHERE product_id = ?').get(productId);
    if (inventoryCount.count > 0) {
        throw new Error('Cannot delete product that is in inventory');
    }
    
    // Delete product
    db.prepare('DELETE FROM products WHERE id = ?').run(productId);
    
    // Log sync event
    logSync(householdId, 'product', 'delete', productId, {});
}

module.exports = {
    lookupProductByUPC,
    createCustomProduct,
    getAllProducts,
    getProductById,
    updateProduct,
    deleteProduct
};
