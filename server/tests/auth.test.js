// Auth API Tests
const request = require('supertest');
const path = require('path');
const fs = require('fs');

// Set test environment before imports
const TEST_DB_PATH = path.join(__dirname, 'test-auth.db');
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

describe('Auth API', () => {
    let authToken;
    let userId;
    let householdId;

    afterAll(() => {
        // Clean up test database
        if (fs.existsSync(TEST_DB_PATH)) {
            fs.unlinkSync(TEST_DB_PATH);
        }
    });

    describe('POST /api/auth/register', () => {
        it('should register a new user successfully', async () => {
            const res = await request(app)
                .post('/api/auth/register')
                .send({
                    email: 'test@example.com',
                    password: 'password123',
                    name: 'Test User',
                    householdName: 'Test Household'
                });

            expect(res.status).toBe(201);
            expect(res.body).toHaveProperty('token');
            expect(res.body).toHaveProperty('user');
            expect(res.body.user.email).toBe('test@example.com');
            expect(res.body.user.name).toBe('Test User');
            expect(res.body).toHaveProperty('householdId');

            authToken = res.body.token;
            userId = res.body.user.id;
            householdId = res.body.householdId;
        });

        it('should fail with missing required fields', async () => {
            const res = await request(app)
                .post('/api/auth/register')
                .send({
                    email: 'test2@example.com'
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Email, password, and name are required');
        });

        it('should fail when email already exists', async () => {
            const res = await request(app)
                .post('/api/auth/register')
                .send({
                    email: 'test@example.com',
                    password: 'password123',
                    name: 'Another User'
                });

            expect(res.status).toBe(409);
            expect(res.body.error).toBe('Email already registered');
        });
    });

    describe('POST /api/auth/login', () => {
        it('should login successfully with valid credentials', async () => {
            const res = await request(app)
                .post('/api/auth/login')
                .send({
                    email: 'test@example.com',
                    password: 'password123'
                });

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('token');
            expect(res.body.user.email).toBe('test@example.com');
        });

        it('should fail with invalid password', async () => {
            const res = await request(app)
                .post('/api/auth/login')
                .send({
                    email: 'test@example.com',
                    password: 'wrongpassword'
                });

            expect(res.status).toBe(401);
            expect(res.body.error).toBe('Invalid credentials');
        });

        it('should fail with non-existent email', async () => {
            const res = await request(app)
                .post('/api/auth/login')
                .send({
                    email: 'nonexistent@example.com',
                    password: 'password123'
                });

            expect(res.status).toBe(401);
            expect(res.body.error).toBe('Invalid credentials');
        });

        it('should fail with missing fields', async () => {
            const res = await request(app)
                .post('/api/auth/login')
                .send({
                    email: 'test@example.com'
                });

            expect(res.status).toBe(400);
            expect(res.body.error).toBe('Email and password are required');
        });
    });

    describe('GET /api/auth/me', () => {
        it('should return current user when authenticated', async () => {
            const res = await request(app)
                .get('/api/auth/me')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body.user.email).toBe('test@example.com');
            expect(res.body).toHaveProperty('household');
        });

        it('should fail without auth token', async () => {
            const res = await request(app)
                .get('/api/auth/me');

            expect(res.status).toBe(401);
        });

        it('should fail with invalid token', async () => {
            const res = await request(app)
                .get('/api/auth/me')
                .set('Authorization', 'Bearer invalid-token');

            expect(res.status).toBe(403);
        });
    });

    describe('Household Invites', () => {
        let inviteCode;

        it('should generate an invite code', async () => {
            const res = await request(app)
                .post('/api/auth/household/invite')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('code');
            expect(res.body.code).toHaveLength(6);
            expect(res.body).toHaveProperty('expiresAt');
            expect(res.body).toHaveProperty('householdName');

            inviteCode = res.body.code;
        });

        it('should validate an invite code', async () => {
            const res = await request(app)
                .get(`/api/auth/household/invite/${inviteCode}`);

            expect(res.status).toBe(200);
            expect(res.body.valid).toBe(true);
            expect(res.body).toHaveProperty('householdId');
            expect(res.body).toHaveProperty('householdName');
            expect(res.body).toHaveProperty('memberCount');
        });

        it('should fail to validate invalid invite code', async () => {
            const res = await request(app)
                .get('/api/auth/household/invite/INVALID');

            expect(res.status).toBe(404);
            expect(res.body.error).toBe('Invalid or expired invite code');
        });

        it('should list household members', async () => {
            const res = await request(app)
                .get('/api/auth/household/members')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('members');
            expect(Array.isArray(res.body.members)).toBe(true);
            expect(res.body.members.length).toBeGreaterThan(0);
        });

        it('should list active invites', async () => {
            const res = await request(app)
                .get('/api/auth/household/invites')
                .set('Authorization', `Bearer ${authToken}`);

            expect(res.status).toBe(200);
            expect(res.body).toHaveProperty('invites');
            expect(Array.isArray(res.body.invites)).toBe(true);
        });
    });
});
