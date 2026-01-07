#!/usr/bin/env node
/**
 * One-time script to seed default locations for all existing households
 * Run this after migrating to client-managed locations
 */

const db = require('../src/models/database');
const { v4: uuidv4 } = require('uuid');

const defaultLocations = [
	{ name: 'Pantry', sortOrder: 0 },
	{ name: 'Fridge', sortOrder: 1 },
	{ name: 'Freezer', sortOrder: 2 },
	{ name: 'Cabinet', sortOrder: 3 },
	{ name: 'Garage', sortOrder: 4 },
	{ name: 'Basement', sortOrder: 5 },
	{ name: 'Other', sortOrder: 6 }
];

try {
	// Get all households
	const households = db.prepare('SELECT DISTINCT household_id FROM users WHERE household_id IS NOT NULL').all();
	console.log(`📊 Found ${households.length} households`);

	for (const household of households) {
		const householdId = household.household_id;

		// Check if locations already exist
		const existingCount = db.prepare('SELECT COUNT(*) as count FROM locations WHERE household_id = ?')
			.get(householdId).count;

		if (existingCount > 0) {
			console.log(`⏭️  Household ${householdId} already has ${existingCount} locations, skipping`);
			continue;
		}

		// Create default locations
		const now = new Date().toISOString();
		for (const loc of defaultLocations) {
			const id = uuidv4();
			db.prepare(`
                INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
                VALUES (?, ?, ?, NULL, 0, ?, ?, ?)
            `).run(id, householdId, loc.name, loc.sortOrder, now, now);
		}

		console.log(`✅ Created ${defaultLocations.length} locations for household ${householdId}`);
	}

	console.log('✅ Migration complete!');
} catch (error) {
	console.error('❌ Migration failed:', error);
	process.exit(1);
}
