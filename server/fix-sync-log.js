const db = require('./src/models/database');

console.log('🔧 [Migration] Fixing sync_log entries with swapped entity_id and action columns...');

// Find all entries where entity_id looks like an action and action looks like a UUID
const corruptedEntries = db.prepare(`
    SELECT id, entity_type, entity_id, action 
    FROM sync_log 
    WHERE entity_id IN ('create', 'update', 'delete')
`).all();

console.log(`📊 Found ${corruptedEntries.length} corrupted entries`);

if (corruptedEntries.length === 0) {
	console.log('✅ No corrupted entries found. Exiting.');
	process.exit(0);
}

// Fix each entry by swapping entity_id and action
const updateStmt = db.prepare(`
    UPDATE sync_log 
    SET entity_id = ?, action = ? 
    WHERE id = ?
`);

const updateMany = db.transaction((entries) => {
	for (const entry of entries) {
		// Swap entity_id and action
		updateStmt.run(entry.action, entry.entity_id, entry.id);
		console.log(`  Fixed: ${entry.entity_type} - entity_id: ${entry.action}, action: ${entry.entity_id}`);
	}
});

updateMany(corruptedEntries);

console.log(`✅ Fixed ${corruptedEntries.length} sync_log entries`);

// Verify the fix
const remainingCorrupted = db.prepare(`
    SELECT COUNT(*) as count 
    FROM sync_log 
    WHERE entity_id IN ('create', 'update', 'delete')
`).get();

if (remainingCorrupted.count === 0) {
	console.log('✅ All entries verified as fixed!');
} else {
	console.log(`⚠️  Still found ${remainingCorrupted.count} potentially corrupted entries`);
}
