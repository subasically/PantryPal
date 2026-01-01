// Inventory API Tests
const request = require('supertest');
const path = require('path');
const fs = require('fs');

// Set test environment before imports
const TEST_DB_PATH = path.join(__dirname, 'test-inventory.db');
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

describe('Inventory API', () => {
    let authToken;
    let householdId;
    let locationId;
    let productId;
    let inventoryId;

    // Setup: Create user, household, get token, and create a location
    beforeAll(async () => {
        // Register user
        const registerRes = await request(app)
            .post('/api/auth/register')
            .send({
                email: 'inventory-test@example.com',
                password: 'password123',
                firstName: 'Inventory',
                lastName: 'User'
            });

        authToken = registerRes.body.token;
        
        // Create household
        const householdRes = await request(app)
            .post('/api/auth/household')
            .set('Authorization', `Bearer ${authToken}`)
            .send({ name: 'Inventory Test Household' });
        
        householdId = householdRes.body.id;

        // Get locations (should have defaults)
        const locationsRes = await request(app)
            .get('/api/locations')
            .set('Authorization', `Bearer ${authToken}`);

        locationId = locationsRes.body.locations[0].id;

        // Create a product
        const productRes = await request(app)
            .post('/api/products')
            .set('Authorization', `Bearer ${authToken}`)
            .send({
                name: 'Test Product',
                brand: 'Test Brand',
                upc: '123456789012'
            });

        productId = productRes.body.id;
    });

    afterAll(() => {
        if (fs.existsSync(TEST_DB_PATH)) {
            fs.unlinkSync(TEST_DB_PATH);
        }
    });

    describe('POST /api/inventory', () => {
        it('should add item to inventory', async () => {
            const res = await request(app)
                .post('/api/inventory')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    productId: productId,
                    quantity: 5,
                    locationId: locationId,
                    expirationDate: '2025-12-31',
                    notes: 'Test notes'
                });

            expect(res.status).toBe(201);
            expect(res.body).toHaveProperty('id');
            expect(res.body.quantity).toBe(5);
            expect(res.body.product_name).toBe('Test Product');
            expect(res.body.notes).toBe('Test notes');

            inventoryId = res.body.id;
        });

        it('should increment quantity for same product/location/expiration', async () => {
            const res = await request(app)
                .post('/api/inventory')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    productId: productId,
                    quantity: 3,
                    locationId: locationId,
                    expirationDate: '2025-12-31'
                });

            expect(res.status).toBe(200);
            expect(res.body.quantity).toBe(8); // 5 + 3
        });

        it('should fail without locationId', async () => {
            const res = await request(app)
                .post('/api/inventory')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    productId: productId,
                    quantity: 1
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Location is required for inventory items');
        });

        it('should fail without productId', async () => {
            const res = await request(app)
                .post('/api/inventory')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    quantity: 1,
                    locationId: locationId
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Product ID is required');
        });

        it('should fail without authentication', async () => {
            const res = await request(app)
                .post('/api/inventory')
                .send({
                    productId: productId,
                    quantity: 1,
                    locationId: locationId
                });

            expect(res.status).toBe(401);
        });
    });

    describe('GET /api/inventory', () => {
        it('should return all inventory items', async () => {
            const res = await request(app)
                .get('/api/inventory')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(Array.isArray(res.body)).toBe(true);
            expect(res.body.length).toBeGreaterThan(0);
            expect(res.body[0]).toHaveProperty('product_name');
            expect(res.body[0]).toHaveProperty('location_name');
        });

        it('should fail without authentication', async () => {
            const res = await request(app)
                .get('/api/inventory');

            expect(res.status).toBe(401);
        });
    });

    describe('PUT /api/inventory/:id', () => {
        it('should update inventory item', async () => {
            const res = await request(app)
                .put(`/api/inventory/${inventoryId}`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    quantity: 10,
                    notes: 'Updated notes',
                    expirationDate: '2026-01-15'
                });

            expect(res.status).toBe(200);
            expect(res.body.quantity).toBe(10);
            expect(res.body.notes).toBe('Updated notes');
            expect(res.body.expiration_date).toBe('2026-01-15');
        });

        it('should fail for non-existent item', async () => {
            const res = await request(app)
                .put('/api/inventory/non-existent-id')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    quantity: 5
                });

            expect(res.status).toBe(404);
        });
    });

    describe('PATCH /api/inventory/:id/quantity', () => {
        it('should increment quantity', async () => {
            const res = await request(app)
                .patch(`/api/inventory/${inventoryId}/quantity`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    adjustment: 5
                });

            expect(res.status).toBe(200);
            expect(res.body.quantity).toBe(15); // 10 + 5
        });

        it('should decrement quantity', async () => {
            const res = await request(app)
                .patch(`/api/inventory/${inventoryId}/quantity`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    adjustment: -3
                });

            expect(res.status).toBe(200);
            expect(res.body.quantity).toBe(12); // 15 - 3
        });

        it('should delete item when quantity reaches 0', async () => {
            // First, create a new item with quantity 1
            const createRes = await request(app)
                .post('/api/inventory')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    productId: productId,
                    quantity: 1,
                    locationId: locationId,
                    expirationDate: '2025-06-01'
                });

            const newItemId = createRes.body.id;

            // Decrement to 0
            const res = await request(app)
                .patch(`/api/inventory/${newItemId}/quantity`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    adjustment: -1
                });

            expect(res.status).toBe(200);
            expect(res.body.deleted).toBe(true);
            expect(res.body.id).toBe(newItemId);
        });

        it('should fail with non-numeric adjustment', async () => {
            const res = await request(app)
                .patch(`/api/inventory/${inventoryId}/quantity`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    adjustment: 'five'
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Adjustment must be a number');
        });
    });

    describe('GET /api/inventory/expiring', () => {
        it('should return expiring items within specified days', async () => {
            const res = await request(app)
                .get('/api/inventory/expiring?days=365')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(Array.isArray(res.body)).toBe(true);
        });
    });

    describe('DELETE /api/inventory/:id', () => {
        it('should delete inventory item', async () => {
            const res = await request(app)
                .delete(`/api/inventory/${inventoryId}`)
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });

        it('should fail for non-existent item', async () => {
            const res = await request(app)
                .delete('/api/inventory/non-existent-id')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(404);
        });
    });
});
