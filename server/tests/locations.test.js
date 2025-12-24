// Locations API Tests
const request = require('supertest');
const path = require('path');
const fs = require('fs');

// Set test environment before imports
const TEST_DB_PATH = path.join(__dirname, 'test-locations.db');
process.env.DATABASE_PATH = TEST_DB_PATH;
process.env.JWT_SECRET = 'test-secret-key';
process.env.NODE_ENV = 'test';

// Clean up before tests
if (fs.existsSync(TEST_DB_PATH)) {
    fs.unlinkSync(TEST_DB_PATH);
}

// Clear module cache to ensure fresh database
delete require.cache[require.resolve('../src/models/database')];

const { createApp } = require('../src/app');

const app = createApp();

describe('Locations API', () => {
    let authToken;
    let householdId;
    let locationId;
    let childLocationId;

    // Setup: Create user
    beforeAll(async () => {
        const registerRes = await request(app)
            .post('/api/auth/register')
            .send({
                email: 'locations-test@example.com',
                password: 'password123',
                name: 'Locations Test User',
                householdName: 'Locations Test Household'
            });

        authToken = registerRes.body.token;
        householdId = registerRes.body.householdId;
    });

    afterAll(() => {
        if (fs.existsSync(TEST_DB_PATH)) {
            fs.unlinkSync(TEST_DB_PATH);
        }
    });

    describe('GET /api/locations', () => {
        it('should return default locations created with household', async () => {
            const res = await request(app)
                .get('/api/locations')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('locations');
            expect(res.body).toHaveProperty('hierarchy');
            expect(Array.isArray(res.body.locations)).toBe(true);
            
            // Should have default locations
            const names = res.body.locations.map(l => l.name);
            expect(names).toContain('Basement Pantry');
            expect(names).toContain('Basement Chest Freezer');
            expect(names).toContain('Kitchen Fridge');

            // Save first location ID for later tests
            locationId = res.body.locations[0].id;
        });

        it('should fail without authentication', async () => {
            const res = await request(app)
                .get('/api/locations');

            expect(res.status).toBe(401);
        });
    });

    describe('GET /api/locations/flat', () => {
        it('should return flat list with full paths', async () => {
            const res = await request(app)
                .get('/api/locations/flat')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(Array.isArray(res.body)).toBe(true);
            expect(res.body[0]).toHaveProperty('id');
            expect(res.body[0]).toHaveProperty('name');
            expect(res.body[0]).toHaveProperty('fullPath');
            expect(res.body[0]).toHaveProperty('level');
        });
    });

    describe('POST /api/locations', () => {
        it('should create a new top-level location', async () => {
            const res = await request(app)
                .post('/api/locations')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Garage Storage'
                });

            expect(res.status).toBe(201);
            expect(res.body.name).toBe('Garage Storage');
            expect(res.body.level).toBe(0);
            expect(res.body.parent_id).toBeNull();
        });

        it('should create a child location', async () => {
            const res = await request(app)
                .post('/api/locations')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'First Shelf',
                    parentId: locationId
                });

            expect(res.status).toBe(201);
            expect(res.body.name).toBe('First Shelf');
            expect(res.body.level).toBe(1);
            expect(res.body.parent_id).toBe(locationId);

            childLocationId = res.body.id;
        });

        it('should create a nested child location', async () => {
            const res = await request(app)
                .post('/api/locations')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Left Side',
                    parentId: childLocationId
                });

            expect(res.status).toBe(201);
            expect(res.body.name).toBe('Left Side');
            expect(res.body.level).toBe(2);
        });

        it('should fail with empty name', async () => {
            const res = await request(app)
                .post('/api/locations')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: '   '
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Location name is required');
        });

        it('should fail with non-existent parent', async () => {
            const res = await request(app)
                .post('/api/locations')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Test Location',
                    parentId: 'non-existent-parent'
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Parent location not found');
        });
    });

    describe('PUT /api/locations/:id', () => {
        it('should update location name', async () => {
            const res = await request(app)
                .put(`/api/locations/${childLocationId}`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Top Shelf'
                });

            expect(res.status).toBe(200);
            expect(res.body.name).toBe('Top Shelf');
        });

        it('should update sort order', async () => {
            const res = await request(app)
                .put(`/api/locations/${childLocationId}`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    sortOrder: 5
                });

            expect(res.status).toBe(200);
            expect(res.body.sort_order).toBe(5);
        });

        it('should fail for non-existent location', async () => {
            const res = await request(app)
                .put('/api/locations/non-existent-id')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Test'
                });

            expect(res.status).toBe(404);
        });
    });

    describe('DELETE /api/locations/:id', () => {
        it('should delete location without inventory', async () => {
            // Create a new location to delete
            const createRes = await request(app)
                .post('/api/locations')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Temporary Location'
                });

            const tempId = createRes.body.id;

            const res = await request(app)
                .delete(`/api/locations/${tempId}`)
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });

        it('should fail to delete location with inventory items', async () => {
            // First, create a product and add inventory to a location
            const productRes = await request(app)
                .post('/api/products')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Test Product for Location',
                    brand: 'Test'
                });

            const productId = productRes.body.id;

            // Add inventory item to the location
            await request(app)
                .post('/api/inventory')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    productId: productId,
                    quantity: 1,
                    locationId: locationId
                });

            // Try to delete the location
            const res = await request(app)
                .delete(`/api/locations/${locationId}`)
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(400);
            expect(res.body.error).toContain('Cannot delete location with inventory items');
        });

        it('should fail for non-existent location', async () => {
            const res = await request(app)
                .delete('/api/locations/non-existent-id')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(404);
        });
    });

    describe('POST /api/locations/seed-defaults', () => {
        it('should not seed if locations already exist', async () => {
            const res = await request(app)
                .post('/api/locations/seed-defaults')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.seeded).toBe(false);
            expect(res.body.message).toBe('Locations already exist');
        });
    });
});
