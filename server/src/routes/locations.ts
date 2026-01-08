import express, { Response } from 'express';
import { v4 as uuidv4 } from 'uuid';
import authenticateToken, { AuthenticatedRequest } from '../middleware/auth';

const router = express.Router();

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

// Seed default locations (if none exist)
router.post('/seed-defaults', (req: AuthenticatedRequest, res: Response) => {
	try {
		const db = getDb();
		const existingCount = db.prepare('SELECT COUNT(*) as count FROM locations WHERE household_id = ?')
			.get(req.user.householdId).count;

		if (existingCount > 0) {
			res.json({ message: 'Locations already exist', seeded: false });
			return;
		}

		const now = new Date().toISOString();
		const defaultLocations = [
			{ name: 'Pantry', sortOrder: 0 },
			{ name: 'Fridge', sortOrder: 1 },
			{ name: 'Freezer', sortOrder: 2 },
			{ name: 'Cabinet', sortOrder: 3 },
			{ name: 'Garage', sortOrder: 4 },
			{ name: 'Basement', sortOrder: 5 },
			{ name: 'Other', sortOrder: 6 }
		];

		for (const loc of defaultLocations) {
			const id = uuidv4();
			db.prepare(`
                INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, NULL, 0, ?, ?, ?)
            `).run(id, req.user.householdId, loc.name, loc.sortOrder, now, now);
		}

		const locations = db.prepare('SELECT * FROM locations WHERE household_id = ?').all(req.user.householdId);
		res.json({ message: 'Default locations created', seeded: true, locations });
	} catch (error) {
		console.error('Error seeding locations:', error);
		res.status(500).json({ error: 'Failed to seed locations' });
	}
});

// Get all locations for household (with hierarchy)
router.get('/', (req: AuthenticatedRequest, res: Response) => {
	try {
		const db = getDb();
		// Locations are now client-managed (created by iOS app during household setup)
		// No longer auto-seeding on first GET request

		const locations = db.prepare(`
            SELECT l.*, 
                   p.name as parent_name,
                   (SELECT COUNT(*) FROM locations WHERE parent_id = l.id) as children_count
            FROM locations l
            LEFT JOIN locations p ON l.parent_id = p.id
            WHERE l.household_id = ?
            ORDER BY l.level, l.sort_order, l.name
        `).all(req.user.householdId);

		// Build hierarchical structure
		const buildHierarchy = (parentId: string | null = null, level: number = 0): any[] => {
			return locations
				.filter((loc: any) => loc.parent_id === parentId)
				.map((loc: any) => ({
					...loc,
					children: buildHierarchy(loc.id, level + 1)
				}));
		};

		res.json({
			locations: locations,
			hierarchy: buildHierarchy()
		});
	} catch (error) {
		console.error('Error fetching locations:', error);
		res.status(500).json({ error: 'Failed to fetch locations' });
	}
});

// Get flat list of all locations with full path (for dropdowns)
router.get('/flat', (req: AuthenticatedRequest, res: Response) => {
	try {
		const db = getDb();
		const locations = db.prepare(`
            SELECT * FROM locations
            WHERE household_id = ?
            ORDER BY level, sort_order, name
        `).all(req.user.householdId);

		// Build full path for each location
		const getFullPath = (locationId: string): string => {
			const parts: string[] = [];
			let current = locations.find((l: any) => l.id === locationId);
			while (current) {
				parts.unshift(current.name);
				current = locations.find((l: any) => l.id === current.parent_id);
			}
			return parts.join(' → ');
		};

		const flatList = locations.map((loc: any) => ({
			id: loc.id,
			name: loc.name,
			fullPath: getFullPath(loc.id),
			level: loc.level,
			parentId: loc.parent_id
		}));

		res.json(flatList);
	} catch (error) {
		console.error('Error fetching flat locations:', error);
		res.status(500).json({ error: 'Failed to fetch locations' });
	}
});

// Create a new location
router.post('/', (req: AuthenticatedRequest, res: Response) => {
	try {
		const db = getDb();
		const { name, parentId } = req.body;

		if (!name?.trim()) {
			res.status(400).json({ error: 'Location name is required' });
			return;
		}

		// Calculate level based on parent
		let level = 0;
		if (parentId) {
			const parent = db.prepare('SELECT level FROM locations WHERE id = ? AND household_id = ?')
				.get(parentId, req.user.householdId);
			if (!parent) {
				res.status(400).json({ error: 'Parent location not found' });
				return;
			}
			level = parent.level + 1;
		}

		// Get max sort order for this parent
		const maxSort = db.prepare(`
            SELECT COALESCE(MAX(sort_order), -1) as max_sort 
            FROM locations 
            WHERE household_id = ? AND parent_id ${parentId ? '= ?' : 'IS NULL'}
        `).get(parentId ? [req.user.householdId, parentId] : [req.user.householdId]);

		const id = uuidv4();
		const now = new Date().toISOString();

		db.prepare(`
            INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        `).run(id, req.user.householdId, name.trim(), parentId || null, level, maxSort.max_sort + 1, now, now);

		const location = db.prepare('SELECT * FROM locations WHERE id = ?').get(id);
		res.status(201).json(location);
	} catch (error) {
		console.error('Error creating location:', error);
		res.status(500).json({ error: 'Failed to create location' });
	}
});

// Update a location
router.put('/:id', (req: AuthenticatedRequest, res: Response) => {
	try {
		const db = getDb();
		const { id } = req.params;
		const { name, sortOrder } = req.body;

		const existing = db.prepare('SELECT * FROM locations WHERE id = ? AND household_id = ?')
			.get(id, req.user.householdId);

		if (!existing) {
			res.status(404).json({ error: 'Location not found' });
			return;
		}

		const updates: string[] = [];
		const params: any[] = [];

		if (name?.trim()) {
			updates.push('name = ?');
			params.push(name.trim());
		}

		if (sortOrder !== undefined) {
			updates.push('sort_order = ?');
			params.push(sortOrder);
		}

		if (updates.length === 0) {
			res.json(existing);
			return;
		}

		updates.push('updated_at = ?');
		params.push(new Date().toISOString());
		params.push(id);

		db.prepare(`UPDATE locations SET ${updates.join(', ')} WHERE id = ?`).run(...params);

		const location = db.prepare('SELECT * FROM locations WHERE id = ?').get(id);
		res.json(location);
	} catch (error) {
		console.error('Error updating location:', error);
		res.status(500).json({ error: 'Failed to update location' });
	}
});

// Delete a location (and reassign children to parent)
router.delete('/:id', (req: AuthenticatedRequest, res: Response) => {
	try {
		const db = getDb();
		const { id } = req.params;

		const existing = db.prepare('SELECT * FROM locations WHERE id = ? AND household_id = ?')
			.get(id, req.user.householdId);

		if (!existing) {
			res.status(404).json({ error: 'Location not found' });
			return;
		}

		// Check if any inventory items use this location
		const itemsUsingLocation = db.prepare('SELECT COUNT(*) as count FROM inventory WHERE location_id = ?').get(id);
		if (itemsUsingLocation.count > 0) {
			res.status(400).json({
				error: 'Cannot delete location with inventory items. Move items first.',
				itemCount: itemsUsingLocation.count
			});
			return;
		}

		// Move children to parent (or make them root)
		db.prepare(`
            UPDATE locations 
            SET parent_id = ?, level = level - 1, updated_at = ?
            WHERE parent_id = ?
        `).run(existing.parent_id, new Date().toISOString(), id);

		// Delete the location
		db.prepare('DELETE FROM locations WHERE id = ?').run(id);

		res.json({ success: true, message: 'Location deleted' });
	} catch (error) {
		console.error('Error deleting location:', error);
		res.status(500).json({ error: 'Failed to delete location' });
	}
});

export default router;
