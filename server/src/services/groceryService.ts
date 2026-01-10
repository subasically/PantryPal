import db from '../models/database';

// Use imported database directly
function getDb() {
	return db;
}

const FREE_LIMIT = 25;

interface GroceryItemData {
	name: string;
	brand?: string;
	upc?: string;
}

interface GroceryItem {
	id: number;
	household_id: string;
	name: string;
	brand: string | null;
	upc: string | null;
	normalized_name: string;
	created_at: string;
}

interface Household {
	id: string;
	is_premium: number;
	premium_expires_at: string | null;
	member_count: number;
}

/**
 * Normalize name for deduplication
 */
function normalizeName(name: string): string {
	return name.trim().toLowerCase().replace(/\s+/g, ' ');
}

/**
 * Check if user can write (Premium required for shared households with multiple members)
 */
function checkWritePermission(householdId: string | null): boolean {
	const db = getDb();
	console.log(`[GroceryWrite] START - householdId: ${householdId}`);

	if (!householdId) {
		console.log(`[GroceryWrite] No household - ALLOW`);
		return true;
	}

	// Get household data including member count
	const household = db.prepare(`
        SELECT h.id, h.is_premium, h.premium_expires_at,
               (SELECT COUNT(*) FROM users WHERE household_id = h.id) as member_count
        FROM households h
        WHERE h.id = ?
    `).get(householdId) as Household | undefined;

	console.log(`[GroceryWrite] Household query result:`, JSON.stringify(household));

	if (!household) {
		console.log(`[GroceryWrite] Household not found - ALLOW (shouldn't happen)`);
		return true;
	}

	// Single-member household: always allow
	if (household.member_count <= 1) {
		console.log(`[GroceryWrite] Single-member household (${household.member_count}) - ALLOW`);
		return true;
	}

	// Multi-member household: require Premium
	const isPremium = household.is_premium === 1 &&
		(!household.premium_expires_at ||
			new Date(household.premium_expires_at) > new Date());

	console.log(`[GroceryWrite] Multi-member household (${household.member_count} members), isPremium: ${isPremium}`);

	return isPremium;
}

/**
 * Check if grocery list is under limit
 */
function checkGroceryLimit(householdId: string | null): boolean {
	const db = getDb();
	if (!householdId) return true;

	const household = db.prepare('SELECT is_premium FROM households WHERE id = ?').get(householdId) as { is_premium: number } | undefined;
	if (household && household.is_premium) return true; // Premium = unlimited

	const count = (db.prepare('SELECT COUNT(*) as count FROM grocery_items WHERE household_id = ?').get(householdId) as { count: number }).count;
	return count < FREE_LIMIT;
}

/**
 * Get all grocery items for household
 */
function getAllGroceryItems(householdId: string | null): GroceryItem[] {
	const db = getDb();
	if (!householdId) {
		return [];
	}

	const items = db.prepare(`
        SELECT id, household_id, name, brand, upc, created_at
        FROM grocery_items
        WHERE household_id = ?
        ORDER BY created_at DESC
    `).all(householdId) as GroceryItem[];

	return items;
}

/**
 * Add item to grocery list
 */
function addGroceryItem(householdId: string | null, itemData: GroceryItemData): GroceryItem {
	const db = getDb();
	const { name, brand, upc } = itemData;

	console.log('[Grocery] addGroceryItem - householdId:', householdId, 'name:', name);

	if (!name?.trim()) {
		throw new Error('Item name required');
	}

	if (!householdId) {
		const error: any = new Error('Please create or join a household first');
		error.requiresHousehold = true;
		throw error;
	}

	// Check write permission
	console.log('[Grocery] BEFORE checkWritePermission');
	const hasWritePermission = checkWritePermission(householdId);
	console.log('[Grocery] AFTER checkWritePermission, result:', hasWritePermission);

	if (!hasWritePermission) {
		console.log('[Grocery] DENYING write permission');
		const error: any = new Error('Household sharing is a Premium feature. Upgrade to add items.');
		error.code = 'PREMIUM_REQUIRED';
		throw error;
	}

	console.log('[Grocery] Write permission GRANTED, checking limit...');

	// Check grocery limit
	if (!checkGroceryLimit(householdId)) {
		const error: any = new Error('Grocery list limit reached');
		error.code = 'LIMIT_REACHED';
		error.limit = FREE_LIMIT;
		throw error;
	}

	const normalizedName = normalizeName(name);

	// Check if already exists
	const existing = db.prepare(`
        SELECT * FROM grocery_items
        WHERE household_id = ? AND normalized_name = ?
    `).get(householdId, normalizedName) as GroceryItem | undefined;

	if (existing) {
		console.log('[Grocery] Item already exists:', normalizedName);
		return existing;
	}

	const result = db.prepare(`
        INSERT INTO grocery_items (household_id, name, brand, upc, normalized_name)
        VALUES (?, ?, ?, ?, ?)
    `).run(householdId, name.trim(), brand || null, upc || null, normalizedName);

	const newItem = db.prepare('SELECT * FROM grocery_items WHERE id = ?').get(result.lastInsertRowid) as GroceryItem;

	console.log('[Grocery] Item added successfully:', newItem.id);

	return newItem;
}

/**
 * Delete grocery item by ID
 */
function deleteGroceryItem(householdId: string | null, itemId: number): void {
	const db = getDb();
	if (!householdId) {
		const error: any = new Error('Please create or join a household first');
		error.requiresHousehold = true;
		throw error;
	}

	// Verify item belongs to user's household
	const item = db.prepare(`
        SELECT id FROM grocery_items
        WHERE id = ? AND household_id = ?
    `).get(itemId, householdId);

	if (!item) {
		throw new Error('Item not found');
	}

	db.prepare('DELETE FROM grocery_items WHERE id = ?').run(itemId);
}

/**
 * Delete grocery item by UPC
 */
function deleteGroceryItemByUPC(householdId: string | null, upc: string): { success: boolean; removed: boolean; count: number } {
	const db = getDb();
	console.log('[Grocery] deleteGroceryItemByUPC - householdId:', householdId, 'upc:', upc);

	if (!householdId) {
		const error: any = new Error('Please create or join a household first');
		error.requiresHousehold = true;
		throw error;
	}

	if (!upc) {
		throw new Error('UPC required');
	}

	const result = db.prepare(`
        DELETE FROM grocery_items
        WHERE household_id = ? AND upc = ?
    `).run(householdId, upc);

	console.log('[Grocery] Deleted by UPC, changes:', result.changes);

	return {
		success: true,
		removed: result.changes > 0,
		count: result.changes
	};
}

/**
 * Delete grocery item by normalized name
 */
function deleteGroceryItemByName(householdId: string | null, normalizedName: string): { success: boolean; removed: boolean; count: number } {
	const db = getDb();
	console.log('[Grocery] deleteGroceryItemByName - householdId:', householdId, 'normalizedName:', normalizedName);

	if (!householdId) {
		const error: any = new Error('Please create or join a household first');
		error.requiresHousehold = true;
		throw error;
	}

	if (!normalizedName) {
		throw new Error('Name required');
	}

	const result = db.prepare(`
        DELETE FROM grocery_items
        WHERE household_id = ? AND normalized_name = ?
    `).run(householdId, normalizedName);

	console.log('[Grocery] Deleted by name, changes:', result.changes);

	return {
		success: true,
		removed: result.changes > 0,
		count: result.changes
	};
}

export default {
	normalizeName,
	checkWritePermission,
	checkGroceryLimit,
	getAllGroceryItems,
	addGroceryItem,
	deleteGroceryItem,
	deleteGroceryItemByUPC,
	deleteGroceryItemByName
};
