// Products API Tests
const request = require('supertest');
const path = require('path');
const fs = require('fs');

// Set test environment before imports
const TEST_DB_PATH = path.join(__dirname, 'test-products.db');
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

describe('Products API', () => {
    let authToken;
    let householdId;
    let customProductId;

    // Setup: Create user and household
    beforeAll(async () => {
        const registerRes = await request(app)
            .post('/api/auth/register')
            .send({
                email: 'products-test@example.com',
                password: 'password123',
                firstName: 'Products',
                lastName: 'User'
            });

        authToken = registerRes.body.token;
        
        // Create household
        const householdRes = await request(app)
            .post('/api/auth/household')
            .set('Authorization', `Bearer ${authToken}`)
            .send({ name: 'Products Test Household' });
        
        householdId = householdRes.body.id;
    });

    afterAll(() => {
        if (fs.existsSync(TEST_DB_PATH)) {
            fs.unlinkSync(TEST_DB_PATH);
        }
    });

    describe('POST /api/products', () => {
        it('should create a custom product', async () => {
            const res = await request(app)
                .post('/api/products')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Homemade Jam',
                    brand: 'Family Recipe',
                    description: 'Grandmas special strawberry jam',
                    category: 'Preserves'
                });

            expect(res.status).toBe(201);
            expect(res.body).toHaveProperty('id');
            expect(res.body.name).toBe('Homemade Jam');
            expect(res.body.brand).toBe('Family Recipe');
            expect(res.body.is_custom).toBe(1);

            customProductId = res.body.id;
        });

        it('should create a custom product with UPC', async () => {
            const res = await request(app)
                .post('/api/products')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Custom Product With UPC',
                    brand: 'Custom Brand',
                    upc: '999888777666'
                });

            expect(res.status).toBe(201);
            expect(res.body.upc).toBe('999888777666');
        });

        it('should fail without name', async () => {
            const res = await request(app)
                .post('/api/products')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    brand: 'Some Brand'
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Product name is required');
        });

        it('should update product with duplicate UPC (upsert behavior)', async () => {
            const res = await request(app)
                .post('/api/products')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Updated Product Name',
                    upc: '999888777666'
                });

            expect(res.status).toBe(200);
            expect(res.body.name).toBe('Updated Product Name');
            expect(res.body.upc).toBe('999888777666');
        });

        it('should fail without authentication', async () => {
            const res = await request(app)
                .post('/api/products')
                .send({
                    name: 'Test Product'
                });

            expect(res.status).toBe(401);
        });
    });

    describe('GET /api/products/lookup/:upc', () => {
        it('should find a custom product by UPC from cache', async () => {
            const res = await request(app)
                .get('/api/products/lookup/999888777666')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.found).toBe(true);
            expect(res.body.product.name).toBe('Updated Product Name'); // After upsert test
            expect(res.body.source).toBe('local');
        });

        it('should return not found for unknown UPC', async () => {
            const res = await request(app)
                .get('/api/products/lookup/000000000000')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.found).toBe(false);
        });
    });

    describe('GET /api/products', () => {
        it('should list all products for household', async () => {
            const res = await request(app)
                .get('/api/products')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(Array.isArray(res.body)).toBe(true);
            expect(res.body.length).toBeGreaterThan(0);
        });
    });

    describe('GET /api/products/:id', () => {
        it('should get a single product', async () => {
            const res = await request(app)
                .get(`/api/products/${customProductId}`)
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.id).toBe(customProductId);
            expect(res.body.name).toBe('Homemade Jam');
        });

        it('should fail for non-existent product', async () => {
            const res = await request(app)
                .get('/api/products/non-existent-id')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(404);
        });
    });

    describe('PUT /api/products/:id', () => {
        it('should update a custom product', async () => {
            const res = await request(app)
                .put(`/api/products/${customProductId}`)
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Updated Homemade Jam',
                    description: 'Now with raspberries!'
                });

            expect(res.status).toBe(200);
            expect(res.body.name).toBe('Updated Homemade Jam');
            expect(res.body.description).toBe('Now with raspberries!');
        });

        it('should fail to update non-existent product', async () => {
            const res = await request(app)
                .put('/api/products/non-existent-id')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Test'
                });

            expect(res.status).toBe(404);
        });
    });

    describe('DELETE /api/products/:id', () => {
        it('should delete a custom product not in inventory', async () => {
            // Create a product to delete
            const createRes = await request(app)
                .post('/api/products')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    name: 'Product To Delete'
                });

            const deleteId = createRes.body.id;

            const res = await request(app)
                .delete(`/api/products/${deleteId}`)
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.success).toBe(true);
        });

        it('should fail for non-existent product', async () => {
            const res = await request(app)
                .delete('/api/products/non-existent-id')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(404);
        });
    });
});
