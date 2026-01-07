const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const { logSync } = require('./syncLogger');
const { isHouseholdPremium, canAddItems, FREE_LIMIT } = require('../utils/premiumHelper');

/**
 * Check inventory limit for household
 * @param {string} householdId - Household ID
 * @returns {boolean} True if can add more items
 */
function checkInventoryLimit(householdId) {
    const count = db.prepare('SELECT COUNT(*) as count FROM inventory WHERE household_id = ?').get(householdId).count;
    return canAddItems(householdId, count);
}

/**
 * Check write permissions for household (Premium required for multi-member households)
 * @param {string} householdId - Household ID
 * @returns {boolean} True if user can write
 */
function checkWritePermission(householdId) {
    // Premium households always have write permission
    if (isHouseholdPremium(householdId)) return true;

    // Free households can write if they have 1 or fewer members
    const memberCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE household_id = ?').get(householdId).count;
    return memberCount <= 1;
}

/**
 * Auto-manage grocery list for Premium households
 * @param {string} householdId - Household ID
 * @param {string} productName - Product name
 * @param {number} newQuantity - New quantity
 * @param {number} oldQuantity - Old quantity
 */
function autoManageGrocery(householdId, productName, newQuantity, oldQuantity) {
    try {
        // Check if household is Premium
        if (!isHouseholdPremium(householdId)) {
            return; // Only auto-manage for Premium
        }

        const normalizedName = productName.trim().toLowerCase().replace(/\s+/g, ' ');

        // If quantity went from >0 to 0, add to grocery
        if (oldQuantity > 0 && newQuantity === 0) {
            const existing = db.prepare(`
                SELECT id FROM grocery_items
                WHERE household_id = ? AND normalized_name = ?
            `).get(householdId, normalizedName);

            if (!existing) {
                db.prepare(`
                    INSERT INTO grocery_items (household_id, name, normalized_name)
                    VALUES (?, ?, ?)
                `).run(householdId, productName.trim(), normalizedName);
                console.log(`[Grocery] Auto-added "${productName}" to grocery list (Premium)`);
            }
        }

        // If quantity went from 0 to >0, remove from grocery
        if (oldQuantity === 0 && newQuantity > 0) {
            db.prepare(`
                DELETE FROM grocery_items
                WHERE household_id = ? AND normalized_name = ?
            `).run(householdId, normalizedName);
            console.log(`[Grocery] Auto-removed "${productName}" from grocery list (Premium)`);
        }
    } catch (error) {
        console.error('Auto-manage grocery error:', error);
        // Don't fail the main operation if grocery management fails
    }
}

/**
 * Get all inventory items for household
 * @param {string} householdId - Household ID
 * @returns {Array} Array of inventory items with product details
 */
function getAllInventory(householdId) {
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

    return inventory;
}

/**
 * Get expiring items within specified days
 * @param {string} householdId - Household ID
 * @param {number} days - Number of days to look ahead (default: 7)
 * @returns {Array} Array of expiring inventory items
 */
function getExpiringItems(householdId, days = 7) {
    const inventory = db.prepare(`
        SELECT i.*, p.name as product_name, p.brand as product_brand, 
               p.upc as product_upc, p.image_url as product_image_url,
               l.name as location_name
        FROM inventory i
        JOIN products p ON i.product_id = p.id
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.household_id = ? 
        AND i.expiration_date IS NOT NULL
        AND date(i.expiration_date) <= date('now', '+' || ? || ' days')
        AND date(i.expiration_date) >= date('now')
        ORDER BY i.expiration_date ASC
    `).all(householdId, days);

    return inventory;
}

/**
 * Get expired items
 * @param {string} householdId - Household ID
 * @returns {Array} Array of expired inventory items
 */
function getExpiredItems(householdId) {
    const inventory = db.prepare(`
        SELECT i.*, p.name as product_name, p.brand as product_brand, 
               p.upc as product_upc, p.image_url as product_image_url,
               l.name as location_name
        FROM inventory i
        JOIN products p ON i.product_id = p.id
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.household_id = ? 
        AND i.expiration_date IS NOT NULL
        AND date(i.expiration_date) < date('now')
        ORDER BY i.expiration_date DESC
    `).all(householdId);

    return inventory;
}

/**
 * Add item to inventory
 * @param {string} householdId - Household ID
 * @param {Object} itemData - { productId, quantity, expirationDate, notes, locationId }
 * @returns {Object} Inventory item with product details
 */
function addInventoryItem(householdId, itemData) {
    const { productId, quantity, expirationDate, notes, locationId } = itemData;

    // Check write permission
    if (!checkWritePermission(householdId)) {
        const error = new Error('Household sharing is a Premium feature. Upgrade to add items.');
        error.code = 'PREMIUM_REQUIRED';
        throw error;
    }

    // Check limit
    if (!checkInventoryLimit(householdId)) {
        const error = new Error('Inventory limit reached');
        error.code = 'LIMIT_REACHED';
        error.limit = FREE_LIMIT;
        throw error;
    }

    if (!productId) {
        throw new Error('Product ID is required');
    }

    if (!locationId) {
        const error = new Error('Location is required for inventory items');
        error.code = 'LOCATION_REQUIRED';
        throw error;
    }

    // Verify product exists
    const product = db.prepare('SELECT id FROM products WHERE id = ?').get(productId);
    if (!product) {
        throw new Error('Product not found');
    }

    // Verify location exists and belongs to household
    const location = db.prepare('SELECT id FROM locations WHERE id = ? AND household_id = ?').get(locationId, householdId);
    if (!location) {
        throw new Error('Location not found or does not belong to this household');
    }

    // Check if item already exists (same product, same expiration, same location)
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
        // Update quantity
        const newQuantity = existingItem.quantity + (quantity || 1);
        db.prepare(`
            UPDATE inventory 
            SET quantity = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        `).run(newQuantity, existingItem.id);

        logSync(householdId, 'inventory', existingItem.id, 'update', {
            quantity: newQuantity,
            expirationDate: existingItem.expiration_date,
            notes: existingItem.notes,
            locationId: existingItem.location_id
        });

        const item = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand,
                   p.upc as product_upc, p.image_url as product_image_url,
                   p.category as product_category, l.name as location_name
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.id = ?
        `).get(existingItem.id);

        item._wasUpdated = true; // Flag for route to know to return 200 instead of 201
        return item;
    }

    const inventoryId = uuidv4();
    db.prepare(`
        INSERT INTO inventory (id, product_id, household_id, location_id, quantity, expiration_date, notes)
        VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(inventoryId, productId, householdId, locationId, quantity || 1, expirationDate || null, notes || null);

    logSync(householdId, 'inventory', inventoryId, 'create', {
        productId,
        quantity: quantity || 1,
        expirationDate: expirationDate || null,
        notes: notes || null,
        locationId
    });

    const item = db.prepare(`
        SELECT i.*, p.name as product_name, p.brand as product_brand,
               p.upc as product_upc, p.image_url as product_image_url,
               p.category as product_category, l.name as location_name
        FROM inventory i
        JOIN products p ON i.product_id = p.id
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.id = ?
    `).get(inventoryId);

    return item;
}

/**
 * Update inventory item
 * @param {string} householdId - Household ID
 * @param {string} itemId - Inventory item ID
 * @param {Object} updates - { quantity, expirationDate, notes, locationId }
 * @returns {Object} Updated inventory item
 */
function updateInventoryItem(householdId, itemId, updates) {
    const { quantity, expirationDate, notes, locationId } = updates;

    console.log(`📝 [InventoryService] updateInventoryItem called`);
    console.log(`   - Item ID: ${itemId}`);
    console.log(`   - Household ID: ${householdId}`);
    console.log(`   - Updates:`, JSON.stringify(updates));
    console.log(`   - Expiration date in updates: ${expirationDate === null ? 'NULL (explicit clear)' : expirationDate === undefined ? 'UNDEFINED (not provided)' : expirationDate}`);

    // Check write permission
    if (!checkWritePermission(householdId)) {
        console.log(`❌ [InventoryService] Write permission denied for household: ${householdId}`);
        const error = new Error('Household sharing is a Premium feature. Upgrade to edit items.');
        error.code = 'PREMIUM_REQUIRED';
        throw error;
    }

    const item = db.prepare('SELECT * FROM inventory WHERE id = ? AND household_id = ?').get(itemId, householdId);

    if (!item) {
        console.log(`❌ [InventoryService] Item not found: ${itemId}`);
        throw new Error('Inventory item not found');
    }

    console.log(`📦 [InventoryService] Current item state:`);
    console.log(`   - Current quantity: ${item.quantity}`);
    console.log(`   - Current expiration: ${item.expiration_date || 'null'}`);
    console.log(`   - Current notes: ${item.notes || 'null'}`);
    console.log(`   - Current location: ${item.location_id}`);

    // Location is REQUIRED for all inventory items
    const finalLocationId = locationId !== undefined ? locationId : item.location_id;
    if (!finalLocationId) {
        console.log(`❌ [InventoryService] Location required but not provided`);
        const error = new Error('Location is required for inventory items');
        error.code = 'LOCATION_REQUIRED';
        throw error;
    }

    // Verify location exists and belongs to household
    const location = db.prepare('SELECT id FROM locations WHERE id = ? AND household_id = ?')
        .get(finalLocationId, householdId);
    if (!location) {
        console.log(`❌ [InventoryService] Invalid location: ${finalLocationId}`);
        const error = new Error('Invalid location or location does not belong to this household');
        error.code = 'INVALID_LOCATION';
        throw error;
    }

    const finalQuantity = quantity !== undefined ? quantity : item.quantity;
    const finalExpiration = expirationDate !== undefined ? expirationDate : item.expiration_date;
    const finalNotes = notes !== undefined ? notes : item.notes;
    const finalLocation = locationId !== undefined ? locationId : item.location_id;

    console.log(`💾 [InventoryService] Updating database with:`);
    console.log(`   - Quantity: ${finalQuantity}`);
    console.log(`   - Expiration: ${finalExpiration === null ? 'NULL (clearing)' : finalExpiration || 'null'}`);
    console.log(`   - Notes: ${finalNotes || 'null'}`);
    console.log(`   - Location: ${finalLocation}`);

    db.prepare(`
        UPDATE inventory 
        SET quantity = ?, expiration_date = ?, notes = ?, location_id = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    `).run(
        finalQuantity,
        finalExpiration,
        finalNotes,
        finalLocation,
        itemId
    );

    console.log(`✅ [InventoryService] Database updated successfully`);

    logSync(householdId, 'inventory', itemId, 'update', {
        quantity: finalQuantity,
        expirationDate: finalExpiration,
        notes: finalNotes,
        locationId: finalLocation
    });

    console.log(`✅ [InventoryService] Sync logged`);

    const updated = db.prepare(`
        SELECT i.*, p.name as product_name, p.brand as product_brand, 
               p.upc as product_upc, p.image_url as product_image_url,
               l.name as location_name
        FROM inventory i
        JOIN products p ON i.product_id = p.id
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.id = ?
    `).get(itemId);

    return updated;
}

/**
 * Adjust inventory item quantity (increment/decrement)
 * @param {string} householdId - Household ID
 * @param {string} itemId - Inventory item ID
 * @param {number} adjustment - Positive or negative number
 * @returns {Object} Updated inventory item or { deleted: true, id }
 */
function adjustQuantity(householdId, itemId, adjustment) {
    // Check write permission
    if (!checkWritePermission(householdId)) {
        const error = new Error('Household sharing is a Premium feature. Upgrade to adjust quantity.');
        error.code = 'PREMIUM_REQUIRED';
        throw error;
    }

    if (typeof adjustment !== 'number') {
        throw new Error('Adjustment must be a number');
    }

    const item = db.prepare('SELECT * FROM inventory WHERE id = ? AND household_id = ?').get(itemId, householdId);

    if (!item) {
        throw new Error('Inventory item not found');
    }

    const newQuantity = item.quantity + adjustment;

    // Get product name for grocery management
    const product = db.prepare('SELECT name FROM products WHERE id = ?').get(item.product_id);
    const oldQuantity = item.quantity;

    if (newQuantity <= 0) {
        // Auto-add to grocery if going to 0
        if (product) {
            autoManageGrocery(householdId, product.name, 0, oldQuantity);
        }

        // Remove item if quantity reaches 0
        db.prepare('DELETE FROM inventory WHERE id = ?').run(itemId);

        logSync(householdId, 'inventory', itemId, 'delete', {});

        return { deleted: true, id: itemId };
    }

    db.prepare(`
        UPDATE inventory 
        SET quantity = ?, updated_at = CURRENT_TIMESTAMP
        WHERE id = ?
    `).run(newQuantity, itemId);

    // Auto-remove from grocery if coming back from 0
    if (product) {
        autoManageGrocery(householdId, product.name, newQuantity, oldQuantity);
    }

    logSync(householdId, 'inventory', itemId, 'update', {
        quantity: newQuantity,
        expirationDate: item.expiration_date,
        notes: item.notes,
        locationId: item.location_id
    });

    const updated = db.prepare(`
        SELECT i.*, p.name as product_name, p.brand as product_brand, 
               p.upc as product_upc, p.image_url as product_image_url
        FROM inventory i
        JOIN products p ON i.product_id = p.id
        WHERE i.id = ?
    `).get(itemId);

    return updated;
}

/**
 * Delete inventory item
 * @param {string} householdId - Household ID
 * @param {string} itemId - Inventory item ID
 */
function deleteInventoryItem(householdId, itemId) {
    // Check write permission
    if (!checkWritePermission(householdId)) {
        const error = new Error('Household sharing is a Premium feature. Upgrade to delete items.');
        error.code = 'PREMIUM_REQUIRED';
        throw error;
    }

    const item = db.prepare('SELECT * FROM inventory WHERE id = ? AND household_id = ?').get(itemId, householdId);

    if (!item) {
        throw new Error('Inventory item not found');
    }

    db.prepare('DELETE FROM inventory WHERE id = ?').run(itemId);

    logSync(householdId, 'inventory', itemId, 'delete', {});
}

/**
 * Quick add by UPC (lookup product + add to inventory in one call)
 * @param {string} householdId - Household ID
 * @param {Object} data - { upc, quantity, expirationDate, locationId }
 * @returns {Object} { item, action: 'created' | 'updated' }
 */
async function quickAddByUPC(householdId, data) {
    const { upc, quantity, expirationDate, locationId } = data;
    const db = require('../models/database');
    const { v4: uuidv4 } = require('uuid');
    const { lookupUPC } = require('./upcLookup');
    const { logSync } = require('./syncLogger');

    // Check write permission
    if (!checkWritePermission(householdId)) {
        const error = new Error('Household sharing is a Premium feature. Upgrade to add items.');
        error.code = 'PREMIUM_REQUIRED';
        throw error;
    }

    // Check limit
    if (!checkInventoryLimit(householdId)) {
        const error = new Error('Inventory limit reached');
        error.code = 'LIMIT_REACHED';
        error.limit = require('../utils/premiumHelper').FREE_LIMIT;
        throw error;
    }

    if (!upc) {
        throw new Error('UPC is required');
    }

    if (!locationId) {
        const error = new Error('Location is required for inventory items');
        error.code = 'LOCATION_REQUIRED';
        throw error;
    }

    // Verify location exists and belongs to household
    const location = db.prepare('SELECT id FROM locations WHERE id = ? AND household_id = ?').get(locationId, householdId);
    if (!location) {
        throw new Error('Location not found or does not belong to this household');
    }

    // Find or create product
    let product = db.prepare(`
        SELECT * FROM products 
        WHERE upc = ? AND (household_id IS NULL OR household_id = ?)
    `).get(upc, householdId);

    if (!product) {
        // Try external lookup
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
            const error = new Error('Product not found');
            error.upc = upc;
            error.requiresCustomProduct = true;
            throw error;
        }
    }

    // Check if already in inventory
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
        const newQuantity = existingItem.quantity + (quantity || 1);
        db.prepare(`
            UPDATE inventory 
            SET quantity = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        `).run(newQuantity, existingItem.id);

        logSync(householdId, 'inventory', existingItem.id, 'update', {
            quantity: newQuantity,
            expirationDate: existingItem.expiration_date,
            notes: existingItem.notes,
            locationId: existingItem.location_id
        });

        const item = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand, 
                   p.upc as product_upc, p.image_url as product_image_url,
                   l.name as location_name
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.id = ?
        `).get(existingItem.id);

        return { item, action: 'updated' };
    }

    // Create new inventory entry
    const inventoryId = uuidv4();
    db.prepare(`
        INSERT INTO inventory (id, product_id, household_id, location_id, quantity, expiration_date)
        VALUES (?, ?, ?, ?, ?, ?)
    `).run(inventoryId, product.id, householdId, locationId, quantity || 1, expirationDate || null);

    logSync(householdId, 'inventory', inventoryId, 'create', {
        productId: product.id,
        quantity: quantity || 1,
        expirationDate: expirationDate || null,
        locationId
    });

    const item = db.prepare(`
        SELECT i.*, p.name as product_name, p.brand as product_brand, 
               p.upc as product_upc, p.image_url as product_image_url,
               l.name as location_name
        FROM inventory i
        JOIN products p ON i.product_id = p.id
        LEFT JOIN locations l ON i.location_id = l.id
        WHERE i.id = ?
    `).get(inventoryId);

    return { item, action: 'created' };
}

module.exports = {
    checkInventoryLimit,
    checkWritePermission,
    autoManageGrocery,
    getAllInventory,
    getExpiringItems,
    getExpiredItems,
    addInventoryItem,
    updateInventoryItem,
    adjustQuantity,
    deleteInventoryItem,
    quickAddByUPC
};
