import express, { Request, Response, Router } from 'express';
import { v4 as uuidv4 } from 'uuid';
import type Database from 'better-sqlite3';
import { toSQLite, nowISO } from '../utils/timestamp';
import type { EntityType, SyncOperation } from '../services/syncLogger';

// Get database instance (will use CommonJS require for now)
const db = require('../models/database') as Database.Database;
const authenticateToken = require('../middleware/auth');

const router: Router = express.Router();

/**
 * Extended Express Request with authenticated user
 */
interface AuthenticatedRequest extends Request {
    user: {
        id: string;
        email: string;
        householdId: string;
    };
}

/**
 * Sync change from client
 */
interface SyncChange {
    entityType: EntityType;
    entityId: string;
    action: SyncOperation;
    payload: Record<string, any>;
    clientTimestamp: string;
}

/**
 * Sync log row from database
 */
interface SyncLogRow {
    id: string;
    household_id: string;
    entity_type: string;
    entity_id: string;
    action: string;
    payload: string;
    client_timestamp: string;
    server_timestamp: string;
    synced: number;
}

/**
 * Product row from database
 */
interface ProductRow {
    id: string;
    upc: string | null;
    name: string;
    brand: string | null;
    description: string | null;
    category: string | null;
    image_url: string | null;
    is_custom: number;
    household_id: string | null;
    created_at: string;
    updated_at: string;
}

/**
 * Inventory row with joined product/location data
 */
interface InventoryRowWithJoins {
    id: string;
    product_id: string;
    household_id: string;
    location_id: string | null;
    quantity: number;
    unit: string;
    expiration_date: string | null;
    notes: string | null;
    created_at: string;
    updated_at: string;
    product_name: string;
    product_brand: string | null;
    product_upc: string | null;
    product_image_url: string | null;
    product_category: string | null;
    location_name: string | null;
}

/**
 * Inventory change payload
 */
interface InventoryPayload {
    productId: string;
    locationId?: string | null;
    quantity: number;
    unit?: string;
    expirationDate?: string | null;
    notes?: string | null;
}

/**
 * Product change payload
 */
interface ProductPayload {
    upc?: string | null;
    name: string;
    brand?: string | null;
    description?: string | null;
    category?: string | null;
}

router.use(authenticateToken);

/**
 * GET /api/sync/changes
 * Get changes since last sync
 */
router.get('/changes', (req: Request, res: Response) => {
    try {
        const authReq = req as AuthenticatedRequest;
        const householdId = authReq.user.householdId;
        const since = req.query.since as string | undefined;
        
        console.log(`[Sync] Changes requested by user ${authReq.user.id} (Household: ${householdId}) since ${since || 'beginning'}`);

        let query = `
            SELECT * FROM sync_log 
            WHERE household_id = ?
        `;
        const params: (string | number)[] = [householdId];

        if (since) {
            // Convert ISO timestamp to SQLite format for comparison
            const sqliteTimestamp = toSQLite(since);
            query += ' AND server_timestamp > ?';
            params.push(sqliteTimestamp);
        }

        query += ' ORDER BY server_timestamp ASC';

        const changes = db.prepare(query).all(...params) as SyncLogRow[];
        
        console.log(`[Sync] Returning ${changes.length} changes`);
        
        res.json({
            changes,
            serverTime: nowISO()
        });
    } catch (error) {
        console.error('Get changes error:', error);
        res.status(500).json({ error: 'Failed to get changes' });
    }
});

/**
 * POST /api/sync/push
 * Push local changes to server
 */
router.post('/push', (req: Request, res: Response) => {
    try {
        const authReq = req as AuthenticatedRequest;
        const { changes } = req.body as { changes: SyncChange[] };
        const householdId = authReq.user.householdId;
        
        console.log(`[Sync] Push received from user ${authReq.user.id} (Household: ${householdId}) with ${changes?.length || 0} changes`);

        if (!Array.isArray(changes)) {
            return res.status(400).json({ error: 'Changes must be an array' });
        }

        const results: Array<{ entityId: string; success: boolean; error?: string }> = [];
        const insertLog = db.prepare(`
            INSERT INTO sync_log (id, household_id, entity_type, entity_id, action, payload, client_timestamp, synced)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1)
        `);

        for (const change of changes) {
            const { entityType, entityId, action, payload, clientTimestamp } = change;
            
            console.log(`[Sync] Processing change: ${entityType} ${entityId} (${action})`);

            try {
                // Apply the change
                applyChange(householdId, entityType, entityId, action, payload);

                // Log the sync
                const logId = uuidv4();
                insertLog.run(
                    logId,
                    householdId,
                    entityType,
                    entityId,
                    action,
                    JSON.stringify(payload),
                    clientTimestamp
                );

                results.push({ entityId, success: true });
            } catch (err) {
                const errorMessage = err instanceof Error ? err.message : 'Unknown error';
                console.error('Failed to apply change:', err);
                results.push({ entityId, success: false, error: errorMessage });
            }
        }

        res.json({
            results,
            serverTime: nowISO()
        });
    } catch (error) {
        console.error('Push changes error:', error);
        res.status(500).json({ error: 'Failed to push changes' });
    }
});

/**
 * GET /api/sync/full
 * Full sync - get complete inventory state
 */
router.get('/full', (req: Request, res: Response) => {
    try {
        const authReq = req as AuthenticatedRequest;
        const householdId = authReq.user.householdId;
        console.log(`[Sync] Full sync requested by user ${authReq.user.id} (Household: ${householdId})`);

        const products = db.prepare(`
            SELECT * FROM products 
            WHERE household_id IS NULL OR household_id = ?
        `).all(householdId) as ProductRow[];

        const inventory = db.prepare(`
            SELECT i.*, p.name as product_name, p.brand as product_brand, 
                   p.upc as product_upc, p.image_url as product_image_url,
                   p.category as product_category,
                   l.name as location_name
            FROM inventory i
            JOIN products p ON i.product_id = p.id
            LEFT JOIN locations l ON i.location_id = l.id
            WHERE i.household_id = ?
        `).all(householdId) as InventoryRowWithJoins[];
        
        console.log(`[Sync] Returning ${inventory.length} inventory items and ${products.length} products`);

        res.json({
            products,
            inventory,
            serverTime: nowISO()
        });
    } catch (error) {
        console.error('Full sync error:', error);
        res.status(500).json({ error: 'Failed to perform full sync' });
    }
});

/**
 * Apply a sync change to the database
 */
function applyChange(
    householdId: string,
    entityType: EntityType,
    entityId: string,
    action: SyncOperation,
    payload: Record<string, any>
): void {
    switch (entityType) {
        case 'inventory':
            applyInventoryChange(householdId, entityId, action, payload as InventoryPayload);
            break;
        case 'product':
            applyProductChange(householdId, entityId, action, payload as ProductPayload);
            break;
        case 'location':
            // TODO: Implement location sync
            console.warn(`[Sync] Location sync not yet implemented`);
            break;
        case 'grocery':
            // TODO: Implement grocery sync
            console.warn(`[Sync] Grocery sync not yet implemented`);
            break;
        case 'household':
            // TODO: Implement household sync
            console.warn(`[Sync] Household sync not yet implemented`);
            break;
        default:
            // TypeScript will ensure this is never reached if all EntityType cases are handled
            const exhaustiveCheck: never = entityType;
            throw new Error(`Unknown entity type: ${exhaustiveCheck}`);
    }
}

/**
 * Apply inventory change to database
 */
function applyInventoryChange(
    householdId: string,
    entityId: string,
    action: SyncOperation,
    payload: InventoryPayload
): void {
    switch (action) {
        case 'create':
            db.prepare(`
                INSERT OR REPLACE INTO inventory (id, product_id, household_id, location_id, quantity, unit, expiration_date, notes, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
            `).run(
                entityId,
                payload.productId,
                householdId,
                payload.locationId || null,
                payload.quantity,
                payload.unit || 'pcs',
                payload.expirationDate || null,
                payload.notes || null
            );
            break;
        case 'update':
            db.prepare(`
                UPDATE inventory 
                SET quantity = ?, unit = ?, expiration_date = ?, notes = ?, location_id = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND household_id = ?
            `).run(
                payload.quantity,
                payload.unit || 'pcs',
                payload.expirationDate || null,
                payload.notes || null,
                payload.locationId || null,
                entityId,
                householdId
            );
            break;
        case 'delete':
            db.prepare('DELETE FROM inventory WHERE id = ? AND household_id = ?').run(entityId, householdId);
            break;
        default:
            const exhaustiveCheck: never = action;
            throw new Error(`Unknown action: ${exhaustiveCheck}`);
    }
}

/**
 * Apply product change to database
 */
function applyProductChange(
    householdId: string,
    entityId: string,
    action: SyncOperation,
    payload: ProductPayload
): void {
    switch (action) {
        case 'create':
            db.prepare(`
                INSERT OR REPLACE INTO products (id, upc, name, brand, description, category, is_custom, household_id, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, 1, ?, CURRENT_TIMESTAMP)
            `).run(
                entityId,
                payload.upc || null,
                payload.name,
                payload.brand || null,
                payload.description || null,
                payload.category || null,
                householdId
            );
            break;
        case 'update':
            db.prepare(`
                UPDATE products 
                SET name = ?, brand = ?, description = ?, category = ?, updated_at = CURRENT_TIMESTAMP
                WHERE id = ? AND household_id = ?
            `).run(
                payload.name,
                payload.brand || null,
                payload.description || null,
                payload.category || null,
                entityId,
                householdId
            );
            break;
        case 'delete':
            db.prepare('DELETE FROM products WHERE id = ? AND household_id = ?').run(entityId, householdId);
            break;
        default:
            const exhaustiveCheck: never = action;
            throw new Error(`Unknown action: ${exhaustiveCheck}`);
    }
}

export default router;
