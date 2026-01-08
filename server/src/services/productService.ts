import { v4 as uuidv4 } from 'uuid';
import { Database } from 'better-sqlite3';
import { lookupUPC, UPCLookupResult } from './upcLookup';
import { logSync } from './syncLogger';

// Lazy load database to avoid circular dependencies
let dbInstance: Database | null = null;
function getDb(): Database {
    if (!dbInstance) {
        dbInstance = require('../models/database');
    }
    return dbInstance;
}

interface ProductRow {
    id: string;
    upc: string;
    name: string;
    brand: string | null;
    description: string | null;
    image_url: string | null;
    category: string | null;
    is_custom: number;
    household_id: string | null;
    created_at: string;
    updated_at: string;
}

interface ProductData {
    upc?: string;
    name: string;
    brand?: string;
    description?: string;
    category?: string;
}

interface ProductLookupResult {
    found: boolean;
    product?: ProductRow;
    source?: 'local' | 'api';
    upc?: string;
}

interface CreateProductResult {
    product: ProductRow;
    wasUpdated: boolean;
}

/**
 * Lookup product by UPC (local database first, then external API)
 * @param {string} upc - Product UPC
 * @param {string} householdId - Household ID for sync logging
 * @returns {Object} { found, product, source }
 */
export async function lookupProductByUPC(upc: string, householdId: string): Promise<ProductLookupResult> {
    const db = getDb();
    console.log(`🔍 [ProductService] lookupProductByUPC called with UPC: ${upc}`);

    // Check local database first
    console.log(`   - Checking local database for UPC: ${upc}`);
    let product = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc) as ProductRow | undefined;

    if (product) {
        console.log(`✅ [ProductService] Product found in local database`);
        console.log(`   - Product ID: ${product.id}`);
        console.log(`   - Product name: ${product.name}`);
        console.log(`   - Product brand: ${product.brand || 'null'}`);
        console.log(`   - Is custom: ${product.is_custom}`);
        console.log(`   - Household ID: ${product.household_id || 'null (global)'}`);
        return { found: true, product, source: 'local' };
    }

    console.log(`⚠️ [ProductService] Product not found in local database, calling external API`);

    // Lookup from external API
    const lookupResult: UPCLookupResult = await lookupUPC(upc);

    console.log(`📡 [ProductService] External API lookup result for ${upc}:`);
    console.log(`   - Found: ${lookupResult.found}`);
    if (lookupResult.found) {
        console.log(`   - Name: ${lookupResult.name}`);
        console.log(`   - Brand: ${lookupResult.brand || 'null'}`);
        console.log(`   - UPC returned: ${lookupResult.upc}`);
    }

    if (lookupResult.found) {
        // Cache the product (only if not already cached)
        const existingProduct = db.prepare('SELECT * FROM products WHERE upc = ?').get(lookupResult.upc) as ProductRow | undefined;

        if (!existingProduct) {
            console.log(`💾 [ProductService] Caching product from external API`);
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
            
            // Log for sync - products are global (household_id = householdId from caller)
            if (householdId) {
                logSync(householdId, 'product', productId, 'create', {
                    upc: lookupResult.upc,
                    name: lookupResult.name,
                    brand: lookupResult.brand,
                    description: lookupResult.description,
                    image_url: lookupResult.image_url,
                    category: lookupResult.category,
                    is_custom: false
                });
            }

            product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId) as ProductRow;
            console.log(`✅ [ProductService] Product cached with ID: ${productId}`);
        } else {
            console.log(`ℹ️ [ProductService] Product already cached in database`);
            product = existingProduct;
        }
        return { found: true, product, source: 'api' };
    }

    console.log(`❌ [ProductService] Product not found (local or API) for UPC: ${upc}`);
    return { found: false, upc };
}

/**
 * Create custom product
 * @param {string} householdId - Household ID
 * @param {Object} productData - { upc, name, brand, description, category }
 * @returns {Object} { product, wasUpdated: boolean }
 */
export function createCustomProduct(householdId: string, productData: ProductData): CreateProductResult {
    const db = getDb();
    const { upc, name, brand, description, category } = productData;

    if (!name) {
        throw new Error('Product name is required');
    }

    // If UPC provided, check if product exists
    if (upc) {
        const existing = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc) as ProductRow | undefined;
        if (existing) {
            // Update existing product
            db.prepare(`
                UPDATE products 
                SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
                WHERE upc = ?
            `).run(name, brand, description, category, upc);

            const product = db.prepare('SELECT * FROM products WHERE upc = ?').get(upc) as ProductRow;

            // Log sync event
            logSync(householdId, 'product', product.id, 'update', {
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

    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(id) as ProductRow;

    // Log sync event
    logSync(householdId, 'product', id, 'create', {
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
export function getAllProducts(householdId: string): ProductRow[] {
    const db = getDb();
    const products = db.prepare(`
        SELECT * FROM products 
        WHERE household_id = ? OR household_id IS NULL
        ORDER BY created_at DESC
    `).all(householdId) as ProductRow[];

    return products;
}

/**
 * Get single product by ID
 * @param {string} productId - Product ID
 * @returns {Object} Product object
 */
export function getProductById(productId: string): ProductRow {
    const db = getDb();
    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId) as ProductRow | undefined;

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
export function updateProduct(householdId: string, productId: string, updates: Partial<ProductData>): ProductRow {
    const db = getDb();
    const { name, brand, description, category } = updates;

    // Check if product exists
    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId) as ProductRow | undefined;
    if (!product) {
        throw new Error('Product not found');
    }

    // Update product
    db.prepare(`
        UPDATE products 
        SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    `).run(name, brand, description, category, productId);

    const updatedProduct = db.prepare('SELECT * FROM products WHERE id = ?').get(productId) as ProductRow;

    // Log sync event
    logSync(householdId, 'product', productId, 'update', {
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
export function deleteProduct(householdId: string, productId: string): void {
    const db = getDb();
    
    // Check if product exists
    const product = db.prepare('SELECT * FROM products WHERE id = ?').get(productId) as ProductRow | undefined;
    if (!product) {
        throw new Error('Product not found');
    }

    // Check if product is in inventory
    const inventoryCount = db.prepare('SELECT COUNT(*) as count FROM inventory WHERE product_id = ?').get(productId) as { count: number };
    if (inventoryCount.count > 0) {
        throw new Error('Cannot delete product that is in inventory');
    }

    // Delete product
    db.prepare('DELETE FROM products WHERE id = ?').run(productId);

    // Log sync event
    logSync(householdId, 'product', productId, 'delete', {});
}
