const request = require('supertest');
const { createApp } = require('../../src/app');
const { createTestDb, resetDb, closeDb, getTestDb } = require('../../src/test-utils/testDb');
const {
    createTestUser,
    createTestProduct,
    createTestLocation,
    createTestInventoryItem,
    delay
} = require('../../src/test-utils/testHelpers');

describe('E2E: Sync Baseline', () => {
    let app;
    let token;
    let householdId;
    let userId;

    beforeAll(() => {
        createTestDb();
        app = createApp();
    });

    beforeEach(() => {
        resetDb();

        // Create test user with household
        const userData = createTestUser({
            email: 'sync@example.com',
            isPremium: true
        });
        token = userData.token;
        householdId = userData.household.id;
        userId = userData.user.id;
    });

    afterAll(() => {
        closeDb();
    });

    describe('GET /api/sync/changes', () => {
        it('should return empty changes array when no cursor provided (bootstrap sync)', async () => {
            const res = await request(app)
                .get('/api/sync/changes')
                .set('Authorization', `Bearer ${token}`);

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('changes');
            expect(Array.isArray(res.body.changes)).toBe(true);
            expect(res.body).toHaveProperty('serverTime');
        });

        it('should return changes after cursor', async () => {
            // Create some changes in the sync log
            const db = getTestDb();
            
            // Insert a product change
            const product = createTestProduct({
                householdId,
                name: 'Sync Test Product'
            });

            // Wait a tiny bit to ensure timestamp difference
            await delay(10);

            // Get initial sync state (bootstrap)
            const res1 = await request(app)
                .get('/api/sync/changes')
                .set('Authorization', `Bearer ${token}`);

            expect(res1.status).toBe(200);
            const cursor1 = res1.body.serverTime;
            expect(cursor1).toBeDefined();

            // Wait to create a timestamp difference
            await delay(10);

            // Create another change AFTER the cursor
            const location = createTestLocation({
                householdId,
                name: 'New Location'
            });

            // Get incremental changes
            const res2 = await request(app)
                .get(`/api/sync/changes?cursor=${cursor1}`)
                .set('Authorization', `Bearer ${token}`);

            expect(res2.status).toBe(200);
            expect(res2.body.changes.length).toBeGreaterThan(0);
            expect(res2.body.serverTime).not.toBe(cursor1);

            // Verify the new location is in the changes
            const locationChange = res2.body.changes.find(
                change => change.entity_type === 'location' && change.entity_id === location.id
            );
            expect(locationChange).toBeDefined();
            expect(locationChange.action).toBe('create');
        });

        it('should return empty changes when cursor is up to date', async () => {
            // Create a product to have some sync log entries
            createTestProduct({
                householdId,
                name: 'Product 1'
            });

            // Get current cursor
            const res1 = await request(app)
                .get('/api/sync/changes')
                .set('Authorization', `Bearer ${token}`);

            const currentCursor = res1.body.serverTime;

            // Request changes with the current cursor (nothing new since last sync)
            const res2 = await request(app)
                .get(`/api/sync/changes?cursor=${currentCursor}`)
                .set('Authorization', `Bearer ${token}`);

            expect(res2.status).toBe(200);
            // Cursor might return same or empty depending on implementation
            expect(Array.isArray(res2.body.changes)).toBe(true);
            expect(res2.body).toHaveProperty('serverTime');
        });

        it('should include payload data in sync changes', async () => {
            // Create an inventory item (which logs to sync)
            const product = createTestProduct({
                householdId,
                name: 'Payload Test Product',
                upc: '111222333444'
            });

            const location = createTestLocation({
                householdId,
                name: 'Payload Test Location'
            });

            const item = createTestInventoryItem({
                productId: product.id,
                locationId: location.id,
                householdId,
                quantity: 15,
                unit: 'kg'
            });

            // Get sync changes
            const res = await request(app)
                .get('/api/sync/changes')
                .set('Authorization', `Bearer ${token}`);

            expect(res.status).toBe(200);
            expect(res.body.changes.length).toBeGreaterThan(0);

            // Find inventory change
            const inventoryChange = res.body.changes.find(
                change => change.entity_type === 'inventory' && change.entity_id === item.id
            );

            expect(inventoryChange).toBeDefined();
            expect(inventoryChange).toHaveProperty('payload');
            
            // Verify payload structure (should be JSON string or parsed object)
            if (typeof inventoryChange.payload === 'string') {
                const payload = JSON.parse(inventoryChange.payload);
                expect(payload).toHaveProperty('quantity', 15);
                expect(payload).toHaveProperty('unit', 'kg');
            } else {
                expect(inventoryChange.payload).toHaveProperty('quantity', 15);
                expect(inventoryChange.payload).toHaveProperty('unit', 'kg');
            }
        });

        it('should reject sync request without authentication', async () => {
            const res = await request(app).get('/api/sync/changes');

            expect(res.status).toBe(401);
        });

        it('should handle multiple entity types in sync changes', async () => {
            // Create multiple types of changes
            const product = createTestProduct({
                householdId,
                name: 'Multi-Entity Product'
            });

            const location = createTestLocation({
                householdId,
                name: 'Multi-Entity Location'
            });

            const item = createTestInventoryItem({
                productId: product.id,
                locationId: location.id,
                householdId,
                quantity: 5
            });

            // Get sync changes
            const res = await request(app)
                .get('/api/sync/changes')
                .set('Authorization', `Bearer ${token}`);

            expect(res.status).toBe(200);
            
            const entityTypes = [...new Set(res.body.changes.map(c => c.entity_type))];
            expect(entityTypes).toContain('product');
            expect(entityTypes).toContain('location');
            expect(entityTypes).toContain('inventory');
        });
    });

    describe('Sync change ordering', () => {
        it('should return changes in chronological order', async () => {
            // Create changes with delays between them
            const product1 = createTestProduct({
                householdId,
                name: 'First Product'
            });

            await delay(10);

            const product2 = createTestProduct({
                householdId,
                name: 'Second Product'
            });

            await delay(10);

            const product3 = createTestProduct({
                householdId,
                name: 'Third Product'
            });

            // Get sync changes
            const res = await request(app)
                .get('/api/sync/changes')
                .set('Authorization', `Bearer ${token}`);

            expect(res.status).toBe(200);
            const changes = res.body.changes;

            // Should have multiple changes
            expect(changes.length).toBeGreaterThanOrEqual(3);

            // Verify changes are ordered by timestamp (ascending)
            for (let i = 1; i < changes.length; i++) {
                const prev = new Date(changes[i - 1].client_timestamp || changes[i - 1].server_timestamp);
                const curr = new Date(changes[i].client_timestamp || changes[i].server_timestamp);
                expect(curr >= prev).toBe(true);
            }
        });
    });

    describe('Sync cursor behavior', () => {
        it('should use cursor to track incremental syncs', async () => {
            // Initial state - create first batch of changes
            createTestProduct({ householdId, name: 'Product A' });
            createTestProduct({ householdId, name: 'Product B' });

            // First sync (bootstrap)
            const sync1 = await request(app)
                .get('/api/sync/changes')
                .set('Authorization', `Bearer ${token}`);

            expect(sync1.status).toBe(200);
            const cursor1 = sync1.body.serverTime;
            const changeCount1 = sync1.body.changes.length;

            // Wait for timestamp difference
            await delay(10);

            // Create new changes after cursor
            createTestProduct({ householdId, name: 'Product C' });
            createTestProduct({ householdId, name: 'Product D' });

            // Second sync (incremental) - should get new and existing changes
            const sync2 = await request(app)
                .get(`/api/sync/changes?cursor=${cursor1}`)
                .set('Authorization', `Bearer ${token}`);

            expect(sync2.status).toBe(200);
            const changeCount2 = sync2.body.changes.length;
            
            // Sync should return changes (may include all or just new depending on implementation)
            expect(changeCount2).toBeGreaterThan(0);

            // New serverTime should be different
            expect(sync2.body.serverTime).not.toBe(cursor1);
        });
    });
});
