import express, { Response } from 'express';
const router = express.Router();
import { v4 as uuidv4 } from 'uuid';
import authenticateToken, { AuthenticatedRequest } from '../middleware/auth';
import pushService from '../services/pushNotifications';
import { logSync } from '../services/syncLogger';
import { isHouseholdPremium } from '../utils/premiumHelper';

// Lazy load database
let dbInstance: any = null;
function getDb() {
	if (!dbInstance) {
		dbInstance = require('../models/database').default;
	}
	return dbInstance;
}

// All routes require authentication
router.use(authenticateToken);

interface ProductRow {
	id: string;
	name: string;
	brand: string | null;
	upc: string;
	image_url: string | null;
	household_id: string | null;
}

interface InventoryItemRow {
	id: string;
	product_id: string;
	household_id: string;
	quantity: number;
	expiration_date: string | null;
	notes: string | null;
	location_id: string | null;
	product_name: string;
	product_brand: string | null;
}

interface CheckoutHistoryRow {
	id: string;
	product_id: string;
	household_id: string;
	user_id: string;
	quantity: number;
	checked_out_at: string;
	product_name: string;
	product_brand: string | null;
	product_image: string | null;
	user_name: string;
}

/**
 * Helper: Auto-manage grocery list for Premium households
 */
function autoManageGrocery(householdId: string, productName: string, newQuantity: number, oldQuantity: number): boolean {
	try {
		// Check if household is Premium (with expiration support)
		if (!isHouseholdPremium(householdId)) {
			return false; // Only auto-manage for Premium
		}

		const normalizedName = productName.trim().toLowerCase().replace(/\s+/g, ' ');

		// If quantity went from >0 to 0, add to grocery
		if (oldQuantity > 0 && newQuantity === 0) {
			const db = getDb();
			const existing = db.prepare(`
                SELECT id FROM grocery_items
                WHERE household_id = ? AND normalized_name = ?
            `).get(householdId, normalizedName);

			if (!existing) {
				db.prepare(`
                    INSERT INTO grocery_items (household_id, name, normalized_name)
                    VALUES (?, ?, ?)
                `).run(householdId, productName.trim(), normalizedName);
				console.log(`[Grocery] Auto-added "${productName}" to grocery list (Premium, checkout)`);
				return true; // Item was added
			}
		}

		return false; // No action taken
	} catch (error) {
		console.error('Auto-manage grocery error (checkout):', error);
		return false;
	}
}

/**
 * @route   POST /api/checkout/scan
 * @desc    Checkout an item by UPC (quick scan mode - reduces quantity by 1)
 * @access  Private
 */
router.post('/scan', (req: AuthenticatedRequest, res: Response) => {
	try {
		const { upc } = req.body;
		console.log(`[Checkout] Scan request - UPC: ${upc}, User: ${req.user!.id}, Household: ${req.user!.householdId}`);

		if (!upc) {
			return res.status(400).json({ error: 'UPC is required' });
		}

		const db = getDb();

		// 1. Check for household-specific custom product first (with custom UPC format)
		const customUpc = `${upc}-${req.user!.householdId}`;
		let product = db.prepare(`
            SELECT * FROM products WHERE upc = ?
        `).get(customUpc) as ProductRow | undefined;

		// 2. If not found, check global products
		if (!product) {
			product = db.prepare(`
                SELECT * FROM products 
                WHERE upc = ? AND (household_id IS NULL OR household_id = ?)
            `).get(upc, req.user!.householdId) as ProductRow | undefined;
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
        `).get(product.id, req.user!.householdId) as InventoryItemRow | undefined;

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

		const oldQuantity = inventoryItem.quantity;
		const _newQuantity = oldQuantity - 1;
		const now = new Date().toISOString();
		const checkoutId = uuidv4();

		// Record checkout in history (with de-dupe protection)
		const recentDuplicate = db.prepare(`
            SELECT id FROM checkout_history
            WHERE household_id = ? 
            AND product_id = ? 
            AND user_id = ?
            AND checked_out_at > datetime('now', '-2 seconds')
        `).get(req.user!.householdId, product.id, req.user!.id);

		if (!recentDuplicate) {
			db.prepare(`
                INSERT INTO checkout_history (id, inventory_id, product_id, household_id, user_id, quantity, checked_out_at)
                VALUES (?, ?, ?, ?, ?, 1, ?)
            `).run(checkoutId, inventoryItem.id, product.id, req.user!.householdId, req.user!.id, now);

			console.log(`[CheckoutHistory] ✅ Logged checkout for product: ${product.name} by user: ${req.user!.id}`);
		} else {
			console.log(`[CheckoutHistory] ⚠️ Skipped duplicate checkout for product: ${product.name} (within 2s)`);
		}

		// Reduce quantity or delete if last one
		if (inventoryItem.quantity <= 1) {
			db.prepare('DELETE FROM inventory WHERE id = ?').run(inventoryItem.id);
			if (req.user!.householdId) {
				logSync(req.user!.householdId, 'inventory', inventoryItem.id, 'delete', {});
			}
		} else {
			db.prepare('UPDATE inventory SET quantity = quantity - 1, updated_at = ? WHERE id = ?')
				.run(now, inventoryItem.id);

			if (req.user!.householdId) {
				logSync(req.user!.householdId, 'inventory', inventoryItem.id, 'update', {
					quantity: inventoryItem.quantity - 1,
					expirationDate: inventoryItem.expiration_date,
					notes: inventoryItem.notes,
					locationId: inventoryItem.location_id
				});
			}
		}

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
			checkoutId: checkoutId,
			productName: product.brand ? `${product.brand} ${product.name}` : product.name
		});

		// Send push notification to household members (async, don't wait)
		const itemName = product.brand ? `${product.brand} ${product.name}` : product.name;
		if (req.user!.householdId) {
			pushService.sendCheckoutNotification(
				req.user!.householdId,
				req.user!.id,
				itemName,
				inventoryItem.quantity - 1
			).catch(err => console.error('Failed to send checkout notification:', err));
		}
	} catch (error) {
		console.error('Error during checkout scan:', error);
		res.status(500).json({ error: 'Failed to process checkout' });
	}
});

/**
 * @route   GET /api/checkout/history
 * @desc    Get checkout history
 * @access  Private
 */
router.get('/history', (req: AuthenticatedRequest, res: Response) => {
	try {
		const { startDate, endDate, limit = '50', offset = '0' } = req.query;
		const db = getDb();

		let query = `
            SELECT 
                ch.*,
                p.name as product_name,
                p.brand as product_brand,
                p.image_url as product_image,
                (u.first_name || ' ' || u.last_name) as user_name
            FROM checkout_history ch
            JOIN products p ON ch.product_id = p.id
            JOIN users u ON ch.user_id = u.id
            WHERE ch.household_id = ?
        `;
		const params: any[] = [req.user!.householdId];

		if (startDate) {
			query += ' AND ch.checked_out_at >= ?';
			params.push(startDate);
		}

		if (endDate) {
			query += ' AND ch.checked_out_at <= ?';
			params.push(endDate);
		}

		query += ' ORDER BY ch.checked_out_at DESC LIMIT ? OFFSET ?';
		params.push(parseInt(limit as string), parseInt(offset as string));

		const history = db.prepare(query).all(...params) as CheckoutHistoryRow[];

		console.log(`[CheckoutHistory] 📊 Fetched ${history.length} history items for household: ${req.user!.householdId}`);
		if (history.length > 0) {
			console.log(`[CheckoutHistory] 📊 First item - user_name: '${history[0].user_name}', user_id: '${history[0].user_id}'`);
		}

		// Get total count
		let countQuery = `
            SELECT COUNT(*) as total FROM checkout_history ch
            WHERE ch.household_id = ?
        `;
		const countParams: any[] = [req.user!.householdId];

		if (startDate) {
			countQuery += ' AND ch.checked_out_at >= ?';
			countParams.push(startDate);
		}
		if (endDate) {
			countQuery += ' AND ch.checked_out_at <= ?';
			countParams.push(endDate);
		}

		const total = db.prepare(countQuery).get(...countParams) as { total: number };

		res.json({
			history: history,
			pagination: {
				total: total.total,
				limit: parseInt(limit as string),
				offset: parseInt(offset as string)
			}
		});
	} catch (error) {
		console.error('Error fetching checkout history:', error);
		res.status(500).json({ error: 'Failed to fetch checkout history' });
	}
});

/**
 * @route   GET /api/checkout/stats
 * @desc    Get consumption stats (for future analytics)
 * @access  Private
 */
router.get('/stats', (req: AuthenticatedRequest, res: Response) => {
	try {
		const { days = '30' } = req.query;
		const startDate = new Date();
		startDate.setDate(startDate.getDate() - parseInt(days as string));

		const db = getDb();

		// Total items checked out
		const totalCheckouts = db.prepare(`
            SELECT COUNT(*) as total, SUM(quantity) as total_quantity
            FROM checkout_history
            WHERE household_id = ? AND checked_out_at >= ?
        `).get(req.user!.householdId, startDate.toISOString()) as { total: number; total_quantity: number };

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
        `).all(req.user!.householdId, startDate.toISOString());

		// Consumption by day
		const byDay = db.prepare(`
            SELECT 
                DATE(checked_out_at) as date,
                SUM(quantity) as total
            FROM checkout_history
            WHERE household_id = ? AND checked_out_at >= ?
            GROUP BY DATE(checked_out_at)
            ORDER BY date DESC
        `).all(req.user!.householdId, startDate.toISOString());

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

export default router;
