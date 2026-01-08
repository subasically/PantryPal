import express, { Response } from 'express';
import authenticateToken, { AuthenticatedRequest } from '../middleware/auth';
import groceryService from '../services/groceryService';

const router = express.Router();

console.log('🔵 [Grocery Routes] Module loaded - VERSION 2025-12-30-19:30');

const FREE_LIMIT = 25;

// GET /api/grocery - Get all grocery items for household
router.get('/', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	try {
		console.log(`🛒 [Grocery GET] Fetching items for household: ${req.user.householdId}`);
		const items = groceryService.getAllGroceryItems(req.user.householdId);
		console.log(`🛒 [Grocery GET] Returning ${items.length} items for household ${req.user.householdId}`);
		res.json(items);
	} catch (error) {
		console.error('Error fetching grocery items:', error);
		res.status(500).json({ error: 'Failed to fetch grocery items' });
	}
});

// POST /api/grocery - Add item to grocery list
router.post('/', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	const { name, brand, upc } = req.body;

	console.log('[Grocery] POST request - householdId:', req.user.householdId, 'name:', name);

	try {
		const newItem = groceryService.addGroceryItem(req.user.householdId, { name, brand, upc });
		const status = newItem.id ? 201 : 200; // 200 if already exists (idempotent)
		res.status(status).json(newItem);
	} catch (error) {
		console.error('Error adding grocery item:', error);
		const err = error as any;
		if (err.requiresHousehold) {
			res.status(400).json({
				error: err.message,
				requiresHousehold: true
			});
			return;
		}
		if (err.code === 'PREMIUM_REQUIRED') {
			res.status(403).json({
				error: err.message,
				code: err.code,
				upgradeRequired: true
			});
			return;
		}
		if (err.code === 'LIMIT_REACHED') {
			res.status(403).json({
				error: err.message,
				code: err.code,
				limit: err.limit || FREE_LIMIT,
				upgradeRequired: true
			});
			return;
		}
		res.status(500).json({ error: 'Failed to add grocery item' });
	}
});

// DELETE /api/grocery/:id - Remove item from grocery list
router.delete('/:id', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	const itemId = parseInt(req.params.id);

	try {
		groceryService.deleteGroceryItem(req.user.householdId, itemId);
		res.json({ success: true });
	} catch (error) {
		console.error('Error deleting grocery item:', error);
		const err = error as any;
		if (err.requiresHousehold) {
			res.status(400).json({
				error: err.message,
				requiresHousehold: true
			});
			return;
		}
		if (err.message === 'Item not found') {
			res.status(404).json({ error: err.message });
			return;
		}
		res.status(500).json({ error: 'Failed to delete grocery item' });
	}
});

// DELETE /api/grocery/by-upc/:upc - Remove item by UPC (for auto-remove on restock)
router.delete('/by-upc/:upc', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	const { upc } = req.params;

	console.log('[Grocery] DELETE by-upc request - householdId:', req.user.householdId, 'upc:', upc);

	try {
		const result = groceryService.deleteGroceryItemByUPC(req.user.householdId, upc);
		console.log('[Grocery] Deleted by UPC, result:', result);
		res.json(result);
	} catch (error) {
		console.error('Error deleting grocery item by UPC:', error);
		const err = error as any;
		if (err.requiresHousehold) {
			res.status(400).json({
				error: err.message,
				requiresHousehold: true
			});
			return;
		}
		res.status(500).json({ error: 'Failed to delete grocery item' });
	}
});

// DELETE /api/grocery/by-name/:normalizedName - Remove item by normalized name (for auto-remove on restock)
router.delete('/by-name/:normalizedName', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	const { normalizedName } = req.params;

	console.log('[Grocery] DELETE by-name request - householdId:', req.user.householdId, 'normalizedName:', normalizedName);

	try {
		const result = groceryService.deleteGroceryItemByName(req.user.householdId, normalizedName);
		console.log('[Grocery] Deleted by name, result:', result);
		res.json(result);
	} catch (error) {
		console.error('Error deleting grocery item by name:', error);
		const err = error as any;
		if (err.requiresHousehold) {
			res.status(400).json({
				error: err.message,
				requiresHousehold: true
			});
			return;
		}
		res.status(500).json({ error: 'Failed to delete grocery item' });
	}
});

export default router;
