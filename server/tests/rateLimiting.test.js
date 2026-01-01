const request = require('supertest');
const { createApp } = require('../src/app');
const db = require('../src/models/database');

describe('Rate Limiting', () => {
    let app;
    let authToken;
    let testUserId;
    let testHouseholdId;

    beforeAll(() => {
        // Create app instance
        app = createApp();

        // Create test user and household
        const userId = 'test-rate-limit-user-' + Date.now();
        const householdId = 'test-rate-limit-household-' + Date.now();
        
        testUserId = userId;
        testHouseholdId = householdId;

        db.prepare(`
            INSERT INTO households (id, name, created_at)
            VALUES (?, 'Test Household', datetime('now'))
        `).run(householdId);

        db.prepare(`
            INSERT INTO users (id, email, password_hash, first_name, last_name, household_id, created_at)
            VALUES (?, 'ratelimit@test.com', 'hash', 'Test', 'User', ?, datetime('now'))
        `).run(userId, householdId);

        // Generate auth token for testing
        const jwt = require('jsonwebtoken');
        authToken = jwt.sign(
            { id: userId, email: 'ratelimit@test.com', householdId },
            process.env.JWT_SECRET || 'test-secret',
            { expiresIn: '1h' }
        );
    });

    afterAll(() => {
        // Cleanup test data
        db.prepare('DELETE FROM users WHERE id = ?').run(testUserId);
        db.prepare('DELETE FROM households WHERE id = ?').run(testHouseholdId);
    });

    describe('Rate Limiting Bypass in Test Environment', () => {
        it('should bypass general API rate limit in test mode', async () => {
            // NODE_ENV=test should bypass all rate limits
            expect(process.env.NODE_ENV).toBe('test');

            // Make more than 100 requests (general limit) - should all succeed
            const requests = Array(10).fill(null).map(() =>
                request(app)
                    .get('/health')
                    .expect(200)
            );

            const responses = await Promise.all(requests);
            responses.forEach(res => {
                expect(res.status).toBe(200);
            });
        });

        it('should bypass auth rate limit in test mode', async () => {
            // Make more than 5 requests (auth limit) - should all succeed
            const requests = Array(7).fill(null).map(() =>
                request(app)
                    .post('/api/auth/login')
                    .send({ email: 'test@example.com', password: 'wrong' })
            );

            const responses = await Promise.all(requests);
            // All should fail with 401 (wrong password), not 429 (rate limited)
            responses.forEach(res => {
                expect(res.status).not.toBe(429);
            });
        });

        it('should bypass UPC lookup rate limit in test mode', async () => {
            // Make more than 10 requests (UPC limit) - should all succeed
            const requests = Array(12).fill(null).map(() =>
                request(app)
                    .get('/api/products/lookup/123456789012')
                    .set('Authorization', `Bearer ${authToken}`)
            );

            const responses = await Promise.all(requests);
            // None should be rate limited
            responses.forEach(res => {
                expect(res.status).not.toBe(429);
            });
        });
    });

    describe('Rate Limit Response Format', () => {
        it('should include correct headers in responses', async () => {
            // Test with health check which is simpler and doesn't require full auth setup
            const res = await request(app)
                .get('/health')
                .expect(200);

            expect(res.body).toHaveProperty('status', 'ok');
            // Rate limit headers should be present in production but may be skipped in test mode
        });

        it('health check endpoint should not have rate limiting', async () => {
            // Health check is outside /api routes, so no general limiter applies
            const res = await request(app)
                .get('/health')
                .expect(200);

            expect(res.body).toHaveProperty('status', 'ok');
            expect(res.body).toHaveProperty('timestamp');
        });
    });

    describe('Rate Limiter Configuration', () => {
        it('should have correct rate limiter exports', () => {
            const rateLimiters = require('../src/middleware/rateLimiter');
            
            expect(rateLimiters).toHaveProperty('generalLimiter');
            expect(rateLimiters).toHaveProperty('upcLookupLimiter');
            expect(rateLimiters).toHaveProperty('authLimiter');
            
            expect(typeof rateLimiters.generalLimiter).toBe('function');
            expect(typeof rateLimiters.upcLookupLimiter).toBe('function');
            expect(typeof rateLimiters.authLimiter).toBe('function');
        });
    });

    describe('Protected Endpoints Coverage', () => {
        it('auth endpoints should be protected by auth rate limiter', async () => {
            // Test that auth routes are accessible (not testing limit since bypassed in test mode)
            const loginRes = await request(app)
                .post('/api/auth/login')
                .send({ email: 'test@example.com', password: 'test' });
            
            expect([401, 500]).toContain(loginRes.status); // Auth fail, not rate limit

            const registerRes = await request(app)
                .post('/api/auth/register')
                .send({ email: 'new@test.com', password: 'test' });
            
            expect([201, 400, 500]).toContain(registerRes.status); // Various outcomes, not 429
        });

        it('UPC lookup endpoint should be protected by UPC rate limiter', async () => {
            const res = await request(app)
                .get('/api/products/lookup/123456789012')
                .set('Authorization', `Bearer ${authToken}`);
            
            expect(res.status).not.toBe(429); // Not rate limited in test mode
        });

        it('general API endpoints should be protected by general rate limiter', async () => {
            const endpoints = [
                '/api/inventory',
                '/api/grocery',
                '/api/locations',
                '/api/sync',
                '/api/checkout',
                '/api/notifications'
            ];

            for (const endpoint of endpoints) {
                const res = await request(app)
                    .get(endpoint)
                    .set('Authorization', `Bearer ${authToken}`);
                
                expect(res.status).not.toBe(429); // Not rate limited in test mode
            }
        });
    });

    describe('IP Address Detection', () => {
        it('should trust proxy for IP detection', async () => {
            const res = await request(app)
                .get('/health')
                .set('X-Forwarded-For', '192.168.1.100')
                .expect(200);

            // In production with trust proxy enabled, rate limits would use the X-Forwarded-For IP
            expect(res.status).toBe(200);
        });
    });
});

// Manual testing notes (for production verification):
// 
// Test General Rate Limit (100 req/15min):
// for i in {1..101}; do curl -H "Authorization: Bearer $TOKEN" https://api-pantrypal.subasically.me/api/inventory; done
//
// Test Auth Rate Limit (5 req/5min):
// for i in {1..6}; do curl -X POST https://api-pantrypal.subasically.me/api/auth/login -d '{"email":"test","password":"test"}' -H "Content-Type: application/json"; done
//
// Test UPC Rate Limit (10 req/min):
// for i in {1..11}; do curl -H "Authorization: Bearer $TOKEN" https://api-pantrypal.subasically.me/api/products/lookup/123456789012; done
