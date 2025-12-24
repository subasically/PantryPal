// Checkout API Tests
const request = require('supertest');
const path = require('path');
const fs = require('fs');

// Set test environment before imports
const TEST_DB_PATH = path.join(__dirname, 'test-checkout.db');
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

describe('Checkout API', () => {
    let authToken;
    let householdId;
    let locationId;
    let productId;
    let productUpc = '123456789999';

    // Setup: Create user, location, product, and inventory
    beforeAll(async () => {
        // Register user
        const registerRes = await request(app)
            .post('/api/auth/register')
            .send({
                email: 'checkout-test@example.com',
                password: 'password123',
                name: 'Checkout Test User',
                householdName: 'Checkout Test Household'
            });

        authToken = registerRes.body.token;
        householdId = registerRes.body.householdId;

        // Get default location
        const locationsRes = await request(app)
            .get('/api/locations')
            .set('Authorization', `Bearer ${authToken}`);

        locationId = locationsRes.body.locations[0].id;

        // Create a product with UPC
        const productRes = await request(app)
            .post('/api/products')
            .set('Authorization', `Bearer ${authToken}`)
            .send({
                name: 'Checkout Test Product',
                brand: 'Test Brand',
                upc: productUpc
            });

        productId = productRes.body.id;

        // Add to inventory with quantity 5
        await request(app)
            .post('/api/inventory')
            .set('Authorization', `Bearer ${authToken}`)
            .send({
                productId: productId,
                quantity: 5,
                locationId: locationId,
                expirationDate: '2025-12-31'
            });
    });

    afterAll(() => {
        if (fs.existsSync(TEST_DB_PATH)) {
            fs.unlinkSync(TEST_DB_PATH);
        }
    });

    describe('POST /api/checkout/scan', () => {
        it('should checkout item by UPC and reduce quantity', async () => {
            const res = await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    upc: productUpc
                });

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
            expect(res.body.previousQuantity).toBe(5);
            expect(res.body.newQuantity).toBe(4);
            expect(res.body.itemDeleted).toBe(false);
            expect(res.body.product.name).toBe('Checkout Test Product');
            expect(res.body).toHaveProperty('checkoutId');
        });

        it('should continue to reduce quantity on subsequent scans', async () => {
            const res = await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    upc: productUpc
                });

            expect(res.status).toBe(200);
            expect(res.body.previousQuantity).toBe(4);
            expect(res.body.newQuantity).toBe(3);
        });

        it('should fail without UPC', async () => {
            const res = await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({});

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('UPC is required');
        });

        it('should fail for non-existent UPC', async () => {
            const res = await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    upc: '000000000000'
                });

            expect(res.status).toBe(404);
            expect(res.body.found).toBe(false);
        });

        it('should delete item when quantity reaches 0', async () => {
            // Checkout remaining items (3 left)
            await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({ upc: productUpc });

            await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({ upc: productUpc });

            // Last item
            const res = await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({ upc: productUpc });

            expect(res.status).toBe(200);
            expect(res.body.previousQuantity).toBe(1);
            expect(res.body.newQuantity).toBe(0);
            expect(res.body.itemDeleted).toBe(true);
        });

        it('should fail when item not in inventory', async () => {
            // Product exists but no inventory
            const res = await request(app)
                .post('/api/checkout/scan')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    upc: productUpc
                });

            expect(res.status).toBe(404);
            expect(res.body.found).toBe(true);
            expect(res.body.inStock).toBe(false);
        });

        it('should fail without authentication', async () => {
            const res = await request(app)
                .post('/api/checkout/scan')
                .send({
                    upc: productUpc
                });

            expect(res.status).toBe(401);
        });
    });

    describe('GET /api/checkout/history', () => {
        it('should return checkout history', async () => {
            const res = await request(app)
                .get('/api/checkout/history')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('history');
            expect(res.body).toHaveProperty('pagination');
            expect(Array.isArray(res.body.history)).toBe(true);
            expect(res.body.history.length).toBe(5); // We checked out 5 items
            expect(res.body.history[0]).toHaveProperty('product_name');
            expect(res.body.history[0]).toHaveProperty('user_name');
        });

        it('should support pagination', async () => {
            const res = await request(app)
                .get('/api/checkout/history?limit=2&offset=0')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.history.length).toBe(2);
            expect(res.body.pagination.limit).toBe(2);
            expect(res.body.pagination.offset).toBe(0);
            expect(res.body.pagination.total).toBe(5);
        });

        it('should filter by date range', async () => {
            const today = new Date().toISOString().split('T')[0];
            const res = await request(app)
                .get(`/api/checkout/history?startDate=${today}`)
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(Array.isArray(res.body.history)).toBe(true);
        });

        it('should fail without authentication', async () => {
            const res = await request(app)
                .get('/api/checkout/history');

            expect(res.status).toBe(401);
        });
    });

    describe('GET /api/checkout/stats', () => {
        it('should return consumption statistics', async () => {
            const res = await request(app)
                .get('/api/checkout/stats')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('period');
            expect(res.body).toHaveProperty('totalCheckouts');
            expect(res.body).toHaveProperty('totalQuantity');
            expect(res.body).toHaveProperty('topProducts');
            expect(res.body).toHaveProperty('byDay');
            expect(res.body.totalCheckouts).toBe(5);
        });

        it('should support custom day range', async () => {
            const res = await request(app)
                .get('/api/checkout/stats?days=7')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.period).toBe('Last 7 days');
        });

        it('should fail without authentication', async () => {
            const res = await request(app)
                .get('/api/checkout/stats');

            expect(res.status).toBe(401);
        });
    });
});
