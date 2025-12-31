const db = require('../models/database');

/**
 * Log sync operations to sync_log table
 * @param {string} householdId - The household ID
 * @param {string} entityType - Type of entity (product, inventory, location, etc.)
 * @param {string} operation - Operation type (create, update, delete)
 * @param {string} entityId - ID of the entity
 * @param {object} metadata - Additional metadata
 */
function logSync(householdId, entityType, operation, entityId, metadata = {}) {
    try {
        db.prepare(`
            INSERT INTO sync_log (household_id, entity_type, operation, entity_id, metadata)
            VALUES (?, ?, ?, ?, ?)
        `).run(
            householdId,
            entityType,
            operation,
            entityId,
            JSON.stringify(metadata)
        );
    } catch (error) {
        console.error('[Sync Logger] Error logging sync:', error);
        // Don't throw - logging should never break the main operation
    }
}

module.exports = { logSync };
