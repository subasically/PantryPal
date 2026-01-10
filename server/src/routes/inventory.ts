import express, { Request, Response, Router } from 'express';
import authenticateToken from '../middleware/auth';
import * as inventoryService from '../services/inventoryService';

const router: Router = express.Router();

interface AuthenticatedRequest extends Request {
	user: {
		id: string;
		email: string;
		householdId: string;
	};
}

interface ErrorWithCode extends Error {
	code?: string;
	limit?: number;
	upc?: string;
	requiresCustomProduct?: boolean;
}

router.use(authenticateToken);

// Get all inventory items for household
router.get('/', ((req: AuthenticatedRequest, res: Response) => {
	try {
		const inventory = inventoryService.getAllInventory(req.user.householdId);
		res.json(inventory);
	} catch (error) {
		console.error('Get inventory error:', error);
		res.status(500).json({ error: 'Failed to get inventory' });
	}
}) as unknown as express.RequestHandler);

// Get expiring items
router.get('/expiring', ((req: AuthenticatedRequest, res: Response) => {
	try {
		const days = parseInt(req.query.days as string) || 7;
		const inventory = inventoryService.getExpiringItems(req.user.householdId, days);
		res.json(inventory);
	} catch (error) {
		console.error('Get expiring items error:', error);
		res.status(500).json({ error: 'Failed to get expiring items' });
	}
}) as unknown as express.RequestHandler);

// Get expired items
router.get('/expired', ((req: AuthenticatedRequest, res: Response) => {
	try {
		const inventory = inventoryService.getExpiredItems(req.user.householdId);
		res.json(inventory);
	} catch (error) {
		console.error('Get expired items error:', error);
		res.status(500).json({ error: 'Failed to get expired items' });
	}
}) as unknown as express.RequestHandler);

// Add item to inventory
router.post('/', ((req: AuthenticatedRequest, res: Response) => {
	try {
		const { productId, quantity, expirationDate, notes, locationId } = req.body;
		const item = inventoryService.addInventoryItem(req.user.householdId, {
			productId,
			quantity,
			expirationDate,
			notes,
			locationId
		});
		// Return 200 if item was updated, 201 if created
		const status = item._wasUpdated ? 200 : 201;
		delete item._wasUpdated; // Remove internal flag before returning
		res.status(status).json(item);
	} catch (error) {
		console.error('Add inventory error:', error);
		const err = error as ErrorWithCode;
		if (err.code === 'PREMIUM_REQUIRED' || err.code === 'LIMIT_REACHED') {
			res.status(403).json({
				error: err.message,
				code: err.code,
				limit: err.limit,
				upgradeRequired: true
			});
			return;
		}
		if (err.code === 'LOCATION_REQUIRED') {
			res.status(400).json({
				error: err.message,
				code: err.code
			});
			return;
		}
		if (err.message === 'Product ID is required') {
			res.status(400).json({ error: err.message });
			return;
		}
		if (err.message === 'Product not found' || err.message.includes('Location')) {
			res.status(404).json({ error: err.message });
			return;
		}
		res.status(500).json({ error: 'Failed to add item to inventory' });
	}
}) as unknown as express.RequestHandler);

// Quick add by UPC (lookup + add in one call)
router.post('/quick-add', (async (req: AuthenticatedRequest, res: Response) => {
	try {
		const { upc, quantity, expirationDate, locationId } = req.body;

		console.log('📥 [Inventory] quick-add request:', {
			householdId: req.user.householdId,
			upc,
			quantity,
			locationId,
			expirationDate
		});

		const result = await inventoryService.quickAddByUPC(req.user.householdId, {
			upc,
			quantity,
			expirationDate,
			locationId
		});
		res.status(201).json(result);
	} catch (error) {
		console.error('Quick add error:', error);
		const err = error as ErrorWithCode;
		if (err.code === 'PREMIUM_REQUIRED' || err.code === 'LIMIT_REACHED') {
			res.status(403).json({
				error: err.message,
				code: err.code,
				limit: err.limit,
				upgradeRequired: true
			});
			return;
		}
		if (err.code === 'LOCATION_REQUIRED') {
			res.status(400).json({
				error: err.message,
				code: err.code
			});
			return;
		}
		if (err.requiresCustomProduct) {
			res.status(404).json({
				error: err.message,
				upc: err.upc,
				requiresCustomProduct: true
			});
			return;
		}
		if (err.message.includes('not found')) {
			res.status(404).json({ error: err.message });
			return;
		}
		res.status(500).json({ error: 'Failed to quick add item' });
	}
}) as unknown as express.RequestHandler);

// Update inventory item
router.put('/:id', ((req: AuthenticatedRequest, res: Response) => {
	try {
		const { quantity, expirationDate, notes, locationId } = req.body;

		console.log(`📝 [Inventory] Update request for item: ${req.params.id}`);
		console.log(`   - User ID: ${req.user.id}`);
		console.log(`   - Household ID: ${req.user.householdId}`);
		console.log(`   - Request body:`, JSON.stringify(req.body));
		console.log(`   - Expiration date: ${expirationDate === null ? 'NULL (clearing)' : expirationDate === undefined ? 'UNDEFINED (not provided)' : expirationDate}`);

		const updated = inventoryService.updateInventoryItem(req.user.householdId, req.params.id, {
			quantity,
			expirationDate,
			notes,
			locationId
		});

		console.log(`✅ [Inventory] Item updated successfully: ${req.params.id}`);
		console.log(`   - Updated expiration: ${updated.expiration_date || 'null'}`);

		res.json(updated);
	} catch (error) {
		console.error('❌ [Inventory] Update inventory error:', error);
		const err = error as ErrorWithCode;
		if (err.code === 'PREMIUM_REQUIRED') {
			res.status(403).json({
				error: err.message,
				code: err.code,
				upgradeRequired: true
			});
			return;
		}
		if (err.code === 'LOCATION_REQUIRED' || err.code === 'INVALID_LOCATION') {
			res.status(400).json({
				error: err.message,
				code: err.code
			});
			return;
		}
		if (err.message === 'Inventory item not found') {
			res.status(404).json({ error: err.message });
			return;
		}
		res.status(500).json({ error: 'Failed to update inventory item' });
	}
}) as unknown as express.RequestHandler);

// Adjust quantity (increment/decrement)
router.patch('/:id/quantity', ((req: AuthenticatedRequest, res: Response) => {
	try {
		const { adjustment } = req.body;

		if (typeof adjustment !== 'number') {
			res.status(400).json({ error: 'Adjustment must be a number' });
			return;
		}

		const result = inventoryService.adjustQuantity(req.user.householdId, req.params.id, adjustment);
		res.json(result);
	} catch (error) {
		console.error('Adjust quantity error:', error);
		const err = error as ErrorWithCode;
		if (err.code === 'PREMIUM_REQUIRED') {
			res.status(403).json({
				error: err.message,
				code: err.code,
				upgradeRequired: true
			});
			return;
		}
		if (err.message === 'Inventory item not found') {
			res.status(404).json({ error: err.message });
			return;
		}
		res.status(500).json({ error: 'Failed to adjust quantity' });
	}
}) as unknown as express.RequestHandler);

// Delete inventory item
router.delete('/:id', ((req: AuthenticatedRequest, res: Response) => {
	try {
		inventoryService.deleteInventoryItem(req.user.householdId, req.params.id);
		res.json({ success: true });
	} catch (error) {
		console.error('Delete inventory error:', error);
		const err = error as ErrorWithCode;
		if (err.code === 'PREMIUM_REQUIRED') {
			res.status(403).json({
				error: err.message,
				code: err.code,
				upgradeRequired: true
			});
			return;
		}
		if (err.message === 'Inventory item not found') {
			res.status(404).json({ error: err.message });
			return;
		}
		res.status(500).json({ error: 'Failed to delete inventory item' });
	}
}) as unknown as express.RequestHandler);

export default router;
