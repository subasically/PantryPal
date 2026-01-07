import { v4 as uuidv4 } from 'uuid';
import type Database from 'better-sqlite3';
import { toSQLite } from '../utils/timestamp';

/**
 * Valid entity types for sync operations
 */
export type EntityType = 'product' | 'inventory' | 'location' | 'grocery' | 'household';

/**
 * Valid sync operation types
 */
export type SyncOperation = 'create' | 'update' | 'delete';

/**
 * Metadata payload for sync operations
 */
export type SyncMetadata = Record<string, any>;

/**
 * Sync log parameters (named for clarity and type safety)
 */
export interface SyncLogParams {
    householdId: string;
    entityType: EntityType;
    entityId: string;
    operation: SyncOperation;
    metadata?: SyncMetadata;
}

/**
 * Lazy load database to avoid circular dependency issues in tests
 * @returns Database instance
 */
function getDb(): Database.Database {
    return require('../models/database');
}

/**
 * Log sync operations to sync_log table
 * 
 * @param householdId - The household ID
 * @param entityType - Type of entity (product, inventory, location, etc.)
 * @param entityId - ID of the entity
 * @param operation - Operation type (create, update, delete)
 * @param metadata - Additional metadata (optional)
 * 
 * @example
 * ```typescript
 * logSync('household-123', 'product', 'prod-456', 'create', { 
 *   name: 'Milk', brand: 'Organic Valley' 
 * });
 * ```
 */
export function logSync(
    householdId: string,
    entityType: EntityType,
    entityId: string,
    operation: SyncOperation,
    metadata: SyncMetadata = {}
): void {
    try {
        const db = getDb();
        const timestamp = toSQLite(new Date().toISOString());
        
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
            timestamp
        );
    } catch (error) {
        console.error('[Sync Logger] Error logging sync:', error);
        // Don't throw - logging should never break the main operation
    }
}

/**
 * Named parameter version of logSync for improved readability
 * 
 * @param params - Sync log parameters
 * 
 * @example
 * ```typescript
 * logSyncNamed({
 *   householdId: 'household-123',
 *   entityType: 'inventory',
 *   entityId: 'item-789',
 *   operation: 'update',
 *   metadata: { quantity: 5, locationId: 'loc-321' }
 * });
 * ```
 */
export function logSyncNamed(params: SyncLogParams): void {
    const { householdId, entityType, entityId, operation, metadata = {} } = params;
    logSync(householdId, entityType, entityId, operation, metadata);
}
