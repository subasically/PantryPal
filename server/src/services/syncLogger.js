const { v4: uuidv4 } = require('uuid');

// Lazy load database to avoid circular dependency issues in tests
function getDb() {
    return require('../models/database');
}

/**
 * Log sync operations to sync_log table
 * @param {string} householdId - The household ID
 * @param {string} entityType - Type of entity (product, inventory, location, etc.)
 * @param {string} entityId - ID of the entity
 * @param {string} operation - Operation type (create, update, delete)
 * @param {object} metadata - Additional metadata
 */
function logSync(householdId, entityType, entityId, operation, metadata = {}) {
    try {
        const db = getDb();
        db.prepare(`
            INSERT INTO sync_log (id, household_id, entity_type, entity_id, action, payload, client_timestamp)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        `).run(
            uuidv4(),
            householdId,
            entityType,
            entityId,
            operation,
            JSON.stringify(metadata),
            new Date().toISOString()
        );
    } catch (error) {
        console.error('[Sync Logger] Error logging sync:', error);
        // Don't throw - logging should never break the main operation
    }
}

module.exports = { logSync };
