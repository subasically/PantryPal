const express = require('express');
const router = express.Router();
const db = require('../models/database');
const { v4: uuidv4 } = require('uuid');
const authenticateToken = require('../middleware/auth');

// All routes require authentication
router.use(authenticateToken);

// Seed default locations (if none exist)
router.post('/seed-defaults', (req, res) => {
    try {
        const existingCount = db.prepare('SELECT COUNT(*) as count FROM locations WHERE household_id = ?')
            .get(req.user.householdId).count;

        if (existingCount > 0) {
            return res.json({ message: 'Locations already exist', seeded: false });
        }

        const now = new Date().toISOString();
        const defaultLocations = [
            { name: 'Pantry', sortOrder: 0 },
            { name: 'Fridge', sortOrder: 1 },
            { name: 'Freezer', sortOrder: 2 },
            { name: 'Other', sortOrder: 3 }
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
router.get('/', (req, res) => {
    try {
        // Check if locations exist
        const count = db.prepare('SELECT COUNT(*) as count FROM locations WHERE household_id = ?').get(req.user.householdId).count;
        
        if (count === 0) {
            console.log(`[Locations] No locations found for household ${req.user.householdId}. Seeding defaults.`);
            // Seed defaults
            const now = new Date().toISOString();
            const defaultLocations = [
                { name: 'Pantry', sortOrder: 0 },
                { name: 'Fridge', sortOrder: 1 },
                { name: 'Freezer', sortOrder: 2 },
                { name: 'Other', sortOrder: 3 }
            ];

            const insertLocation = db.prepare(`
                INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, NULL, 0, ?, ?, ?)
            `);

            const transaction = db.transaction(() => {
                for (const loc of defaultLocations) {
                    insertLocation.run(uuidv4(), req.user.householdId, loc.name, loc.sortOrder, now, now);
                }
            });
            transaction();
        }

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
        const buildHierarchy = (parentId = null, level = 0) => {
            return locations
                .filter(loc => loc.parent_id === parentId)
                .map(loc => ({
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
router.get('/flat', (req, res) => {
    try {
        const locations = db.prepare(`
            SELECT * FROM locations
            WHERE household_id = ?
            ORDER BY level, sort_order, name
        `).all(req.user.householdId);

        // Build full path for each location
        const getFullPath = (locationId) => {
            const parts = [];
            let current = locations.find(l => l.id === locationId);
            while (current) {
                parts.unshift(current.name);
                current = locations.find(l => l.id === current.parent_id);
            }
            return parts.join(' → ');
        };

        const flatList = locations.map(loc => ({
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
router.post('/', (req, res) => {
    try {
        const { name, parentId } = req.body;

        if (!name?.trim()) {
            return res.status(400).json({ error: 'Location name is required' });
        }

        // Calculate level based on parent
        let level = 0;
        if (parentId) {
            const parent = db.prepare('SELECT level FROM locations WHERE id = ? AND household_id = ?')
                .get(parentId, req.user.householdId);
            if (!parent) {
                return res.status(400).json({ error: 'Parent location not found' });
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
router.put('/:id', (req, res) => {
    try {
        const { id } = req.params;
        const { name, sortOrder } = req.body;

        const existing = db.prepare('SELECT * FROM locations WHERE id = ? AND household_id = ?')
            .get(id, req.user.householdId);

        if (!existing) {
            return res.status(404).json({ error: 'Location not found' });
        }

        const updates = [];
        const params = [];

        if (name?.trim()) {
            updates.push('name = ?');
            params.push(name.trim());
        }

        if (sortOrder !== undefined) {
            updates.push('sort_order = ?');
            params.push(sortOrder);
        }

        if (updates.length === 0) {
            return res.json(existing);
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
router.delete('/:id', (req, res) => {
    try {
        const { id } = req.params;

        const existing = db.prepare('SELECT * FROM locations WHERE id = ? AND household_id = ?')
            .get(id, req.user.householdId);

        if (!existing) {
            return res.status(404).json({ error: 'Location not found' });
        }

        // Check if any inventory items use this location
        const itemsUsingLocation = db.prepare('SELECT COUNT(*) as count FROM inventory WHERE location_id = ?').get(id);
        if (itemsUsingLocation.count > 0) {
            return res.status(400).json({ 
                error: 'Cannot delete location with inventory items. Move items first.',
                itemCount: itemsUsingLocation.count
            });
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

module.exports = router;
