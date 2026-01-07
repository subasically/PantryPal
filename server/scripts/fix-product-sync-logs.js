#!/usr/bin/env node
/**
 * Fix corrupted product sync_log entries
 * Recreates correct sync logs for products that have wrong entity_id/action order
 */

const db = require('../src/models/database');
const { v4: uuidv4 } = require('uuid');

try {
	// Get all products that need sync logs
	const products = db.prepare('SELECT * FROM products WHERE household_id IS NOT NULL').all();

	console.log(`📊 Found ${products.length} custom products`);

	for (const product of products) {
		// Create correct sync log entry
		const syncId = uuidv4();
		db.prepare(`
            INSERT INTO sync_log (id, household_id, entity_type, entity_id, action, payload, client_timestamp, server_timestamp, synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, 0)
        `).run(
			syncId,
			product.household_id,
			'product',
			product.id,  // CORRECT: entity_id is the product ID
			'create',    // CORRECT: action is 'create'
			JSON.stringify({
				upc: product.upc,
				name: product.name,
				brand: product.brand,
				description: product.description,
				category: product.category,
				is_custom: product.is_custom
			}),
			new Date().toISOString()
		);

		console.log(`✅ Created sync log for product: ${product.name} (${product.id})`);
	}

	console.log('✅ Product sync logs fixed!');
} catch (error) {
	console.error('❌ Error:', error);
	process.exit(1);
}
