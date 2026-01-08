const request = require('supertest');
const { createApp } = require('../../src/app');
const { createTestDb, resetDb, closeDb } = require('../../src/test-utils/testDb');
const { createTestUser } = require('../../src/test-utils/testHelpers');

describe('E2E: Health & Auth', () => {
	let app;

	beforeAll(() => {
		createTestDb();
		app = createApp();
	});

	beforeEach(() => {
		resetDb();
	});

	afterAll(() => {
		closeDb();
	});

	describe('GET /health', () => {
		it('should return 200 with status ok', async () => {
			const res = await request(app).get('/health');

			expect(res.status).toBe(200);
			expect(res.body).toHaveProperty('status', 'ok');
			expect(res.body).toHaveProperty('timestamp');
		});
	});

	describe('POST /api/auth/register', () => {
		it('should register a new user with email/password', async () => {
			const res = await request(app)
				.post('/api/auth/register')
				.send({
					email: 'test@example.com',
					password: 'password123',
					householdName: 'Test Household'
				});

			expect(res.status).toBe(201);
			expect(res.body).toHaveProperty('token');
			expect(res.body).toHaveProperty('user');
			expect(res.body.user.email).toBe('test@example.com');
			// Note: householdId may be null initially until household setup is complete
		});

		it('should reject registration with missing email', async () => {
			const res = await request(app)
				.post('/api/auth/register')
				.send({
					password: 'password123',
					householdName: 'Test Household'
				});

			expect(res.status).toBe(400);
			expect(res.body).toHaveProperty('error');
		});

		it('should reject registration with duplicate email', async () => {
			// Register first user
			await request(app)
				.post('/api/auth/register')
				.send({
					email: 'duplicate@example.com',
					password: 'password123',
					householdName: 'First Household'
				});

			// Try to register same email again
			const res = await request(app)
				.post('/api/auth/register')
				.send({
					email: 'duplicate@example.com',
					password: 'password456',
					householdName: 'Second Household'
				});

			expect(res.status).toBe(400);
			expect(res.body.error).toMatch(/already exists/i);
		});
	});

	describe('POST /api/auth/login', () => {
		beforeEach(() => {
			// Create test user for login tests
			createTestUser({
				email: 'login@example.com',
				password: 'password123'
			});
		});

		it('should login with valid credentials', async () => {
			const res = await request(app)
				.post('/api/auth/login')
				.send({
					email: 'login@example.com',
					password: 'password123'
				});

			expect(res.status).toBe(200);
			expect(res.body).toHaveProperty('token');
			expect(res.body).toHaveProperty('user');
			expect(res.body.user.email).toBe('login@example.com');
		});

		it('should reject login with invalid password', async () => {
			const res = await request(app)
				.post('/api/auth/login')
				.send({
					email: 'login@example.com',
					password: 'wrongpassword'
				});

			expect(res.status).toBe(401);
			expect(res.body).toHaveProperty('error');
		});

		it('should reject login with non-existent email', async () => {
			const res = await request(app)
				.post('/api/auth/login')
				.send({
					email: 'nonexistent@example.com',
					password: 'password123'
				});

			expect(res.status).toBe(401);
			expect(res.body).toHaveProperty('error');
		});
	});

	describe('GET /api/auth/me', () => {
		let token;
		let user;

		beforeEach(() => {
			const testData = createTestUser({
				email: 'me@example.com',
				firstName: 'Test',
				lastName: 'User'
			});
			token = testData.token;
			user = testData.user;
		});

		it('should return user data with valid token', async () => {
			const res = await request(app)
				.get('/api/auth/me')
				.set('Authorization', `Bearer ${token}`);

			expect(res.status).toBe(200);
			expect(res.body).toHaveProperty('user');
			expect(res.body.user).toHaveProperty('id', user.id);
			expect(res.body.user).toHaveProperty('email', 'me@example.com');
			expect(res.body.user).toHaveProperty('householdId', user.householdId);
		});

		it('should reject request without token', async () => {
			const res = await request(app).get('/api/auth/me');

			expect(res.status).toBe(401);
			// Middleware uses sendStatus, so body will be empty
		});

		it('should reject request with invalid token', async () => {
			const res = await request(app)
				.get('/api/auth/me')
				.set('Authorization', 'Bearer invalidtoken123');

			expect(res.status).toBe(403);
			// Middleware uses sendStatus, so body will be empty
		});
	});
});
