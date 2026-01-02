const request = require('supertest');
const path = require('path');
const fs = require('fs');

// Set test environment before imports
const TEST_DB_PATH = path.join(__dirname, 'test-subscriptions.db');
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

let app;
let authToken;
let householdId;

describe('Subscriptions API', () => {
    beforeAll(() => {
        // Create app
        app = createApp();
    });

    afterAll(() => {
        // Clean up test database
        if (fs.existsSync(TEST_DB_PATH)) {
            fs.unlinkSync(TEST_DB_PATH);
        }
    });

    // Register and login before tests
    beforeEach(async () => {
        // Register a new user
        const registerRes = await request(app)
            .post('/api/auth/register')
            .send({
                email: `test${Date.now()}@example.com`,
                password: 'testpass123',
                firstName: 'Test',
                lastName: 'User'
            });

        authToken = registerRes.body.token;

        // Create a household
        const householdRes = await request(app)
            .post('/api/auth/household')
            .set('Authorization', `Bearer ${authToken}`)
            .send({
                name: 'Test Household'
            });

        householdId = householdRes.body.id;
    });

    describe('POST /api/subscriptions/validate', () => {
        it('should validate a receipt and activate Premium', async () => {
            const transactionData = {
                transactionId: '1000000123456789',
                productId: 'com.pantrypal.premium.monthly',
                originalTransactionId: '1000000123456789',
                expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString() // 30 days from now
            };

            const res = await request(app)
                .post('/api/subscriptions/validate')
                .set('Authorization', `Bearer ${authToken}`)
                .send(transactionData);

            if (res.statusCode !== 200) {
                console.log('Error response:', res.body);
            }

            expect(res.statusCode).toBe(200);
            expect(res.body.household).toBeDefined();
            expect(res.body.household.isPremium).toBe(true);
            expect(res.body.household.premiumExpiresAt).toBe(transactionData.expiresAt);
            expect(res.body.subscription).toBeDefined();
            expect(res.body.subscription.productId).toBe(transactionData.productId);
            expect(res.body.subscription.isActive).toBe(true);
        });

        it('should fail validation without transactionId', async () => {
            const res = await request(app)
                .post('/api/subscriptions/validate')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    productId: 'com.pantrypal.premium.monthly',
                    originalTransactionId: '1000000123456789',
                    expiresAt: new Date().toISOString()
                });

            expect(res.statusCode).toBe(400);
            expect(res.body.error).toContain('Missing required transaction fields');
        });

        it('should require authentication', async () => {
            const res = await request(app)
                .post('/api/subscriptions/validate')
                .send({
                    transactionId: '1000000123456789',
                    productId: 'com.pantrypal.premium.monthly',
                    originalTransactionId: '1000000123456789',
                    expiresAt: new Date().toISOString()
                });

            expect(res.statusCode).toBe(401);
        });
    });

    describe('GET /api/subscriptions/status', () => {
        it('should return Premium status for household', async () => {
            // First activate Premium
            const transactionData = {
                transactionId: '1000000123456789',
                productId: 'com.pantrypal.premium.annual',
                originalTransactionId: '1000000123456789',
                expiresAt: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString() // 1 year from now
            };

            await request(app)
                .post('/api/subscriptions/validate')
                .set('Authorization', `Bearer ${authToken}`)
                .send(transactionData);

            // Check status
            const res = await request(app)
                .get('/api/subscriptions/status')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.statusCode).toBe(200);
            expect(res.body.isPremium).toBe(true);
            expect(res.body.premiumExpiresAt).toBe(transactionData.expiresAt);
            expect(res.body.householdId).toBe(householdId);
        });

        it('should return false for free users', async () => {
            const res = await request(app)
                .get('/api/subscriptions/status')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.statusCode).toBe(200);
            expect(res.body.isPremium).toBe(false);
            expect(res.body.householdId).toBe(householdId);
        });

        it('should detect expired Premium subscriptions', async () => {
            // Activate Premium with expired date
            const expiredDate = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(); // Yesterday
            
            await request(app)
                .post('/api/subscriptions/validate')
                .set('Authorization', `Bearer ${authToken}`)
                .send({
                    transactionId: '1000000123456789',
                    productId: 'com.pantrypal.premium.monthly',
                    originalTransactionId: '1000000123456789',
                    expiresAt: expiredDate
                });

            // Check status - should be false
            const res = await request(app)
                .get('/api/subscriptions/status')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.statusCode).toBe(200);
            expect(res.body.isPremium).toBe(false);
        });

        it('should require authentication', async () => {
            const res = await request(app)
                .get('/api/subscriptions/status');

            expect(res.statusCode).toBe(401);
        });
    });
});
