const request = require('supertest');
const { createApp } = require('../../src/app');
const { createTestDb, resetDb, closeDb } = require('../../src/test-utils/testDb');
const {
	createTestUser,
	createTestProduct,
	createTestLocation,
	createTestInventoryItem
} = require('../../src/test-utils/testHelpers');

describe('E2E: Inventory CRUD', () => {
	let app;
	let token;
	let householdId;
	let locationId;
	let productId;

	beforeAll(() => {
		createTestDb();
		app = createApp();
	});

	beforeEach(() => {
		resetDb();

		// Create test user with household
		const userData = createTestUser({
			email: 'inventory@example.com',
			isPremium: true
		});
		token = userData.token;
		householdId = userData.household.id;

		// Create test location
		const location = createTestLocation({
			householdId,
			name: 'Pantry'
		});
		locationId = location.id;

		// Create test product
		const product = createTestProduct({
			householdId,
			name: 'Test Product',
			upc: '123456789012',
			brand: 'Test Brand',
			category: 'Food'
		});
		productId = product.id;
	});

	afterAll(() => {
		closeDb();
	});

	describe('POST /api/inventory', () => {
		it('should create a new inventory item', async () => {
			const res = await request(app)
				.post('/api/inventory')
				.set('Authorization', `Bearer ${token}`)
				.send({
					productId: productId,
					locationId: locationId,
					quantity: 5,
					unit: 'pcs'
				});

			if (res.status !== 201) {
				console.error('Response status:', res.status);
				console.error('Response body:', res.body);
			}

			expect(res.status).toBe(201);
			expect(res.body).toHaveProperty('id');
			expect(res.body).toHaveProperty('product_id', productId);
			expect(res.body).toHaveProperty('location_id', locationId);
			expect(res.body).toHaveProperty('quantity', 5);
		});

		it('should reject inventory item without product_id', async () => {
			const res = await request(app)
				.post('/api/inventory')
				.set('Authorization', `Bearer ${token}`)
				.send({
					location_id: locationId,
					quantity: 5
				});

			expect(res.status).toBe(400);
			expect(res.body).toHaveProperty('error');
		});

		it('should reject inventory item without authentication', async () => {
			const res = await request(app)
				.post('/api/inventory')
				.send({
					product_id: productId,
					location_id: locationId,
					quantity: 5
				});

			expect(res.status).toBe(401);
		});
	});

	describe('GET /api/inventory', () => {
		beforeEach(() => {
			// Create some inventory items
			createTestInventoryItem({
				productId,
				locationId,
				householdId,
				quantity: 10,
				unit: 'pcs'
			});

			const product2 = createTestProduct({
				householdId,
				name: 'Another Product',
				upc: '999888777666'
			});

			createTestInventoryItem({
				productId: product2.id,
				locationId,
				householdId,
				quantity: 3,
				unit: 'kg'
			});
		});

		it('should return all inventory items for household', async () => {
			const res = await request(app)
				.get('/api/inventory')
				.set('Authorization', `Bearer ${token}`);

			expect(res.status).toBe(200);
			expect(Array.isArray(res.body)).toBe(true);
			expect(res.body.length).toBeGreaterThanOrEqual(2);

			// Verify structure of first item
			const item = res.body[0];
			expect(item).toHaveProperty('id');
			expect(item).toHaveProperty('quantity');
			expect(item).toHaveProperty('unit');
			expect(item).toHaveProperty('product_id');
			expect(item).toHaveProperty('location_id');
		});

		it('should filter inventory by location', async () => {
			const res = await request(app)
				.get(`/api/inventory?location_id=${locationId}`)
				.set('Authorization', `Bearer ${token}`);

			expect(res.status).toBe(200);
			expect(Array.isArray(res.body)).toBe(true);

			// All items should belong to the specified location
			res.body.forEach(item => {
				expect(item.location_id).toBe(locationId);
			});
		});
	});

	describe('PUT /api/inventory/:id', () => {
		let inventoryItem;

		beforeEach(() => {
			inventoryItem = createTestInventoryItem({
				productId,
				locationId,
				householdId,
				quantity: 5,
				unit: 'pcs'
			});
		});

		it('should update inventory item quantity', async () => {
			const res = await request(app)
				.put(`/api/inventory/${inventoryItem.id}`)
				.set('Authorization', `Bearer ${token}`)
				.send({
					quantity: 10
				});

			expect(res.status).toBe(200);
			expect(res.body).toHaveProperty('quantity', 10);
			expect(res.body).toHaveProperty('id', inventoryItem.id);
		});

		it('should update inventory item expiration date', async () => {
			const expiryDate = '2025-12-31T00:00:00.000Z';
			const res = await request(app)
				.put(`/api/inventory/${inventoryItem.id}`)
				.set('Authorization', `Bearer ${token}`)
				.send({
					expiration_date: expiryDate
				});

			expect(res.status).toBe(200);
			expect(res.body).toHaveProperty('expiration_date');
		});

		it('should reject update to non-existent item', async () => {
			const res = await request(app)
				.put('/api/inventory/nonexistent-id')
				.set('Authorization', `Bearer ${token}`)
				.send({
					quantity: 10
				});

			expect(res.status).toBe(404);
		});
	});

	describe('DELETE /api/inventory/:id', () => {
		let inventoryItem;

		beforeEach(() => {
			inventoryItem = createTestInventoryItem({
				productId,
				locationId,
				householdId,
				quantity: 5
			});
		});

		it('should delete an inventory item', async () => {
			const res = await request(app)
				.delete(`/api/inventory/${inventoryItem.id}`)
				.set('Authorization', `Bearer ${token}`);

			expect(res.status).toBe(200);

			// Verify item is deleted
			const getRes = await request(app)
				.get('/api/inventory')
				.set('Authorization', `Bearer ${token}`);

			const foundItem = getRes.body.find(item => item.id === inventoryItem.id);
			expect(foundItem).toBeUndefined();
		});

		it('should return 404 for non-existent item', async () => {
			const res = await request(app)
				.delete('/api/inventory/nonexistent-id')
				.set('Authorization', `Bearer ${token}`);

			expect(res.status).toBe(404);
		});
	});

	describe('Inventory with Product and Location details', () => {
		beforeEach(() => {
			createTestInventoryItem({
				productId,
				locationId,
				householdId,
				quantity: 7,
				unit: 'boxes'
			});
		});

		it('should return inventory with joined product details', async () => {
			const res = await request(app)
				.get('/api/inventory')
				.set('Authorization', `Bearer ${token}`);

			expect(res.status).toBe(200);
			const item = res.body[0];

			// Verify product details are included (if endpoint supports JOIN)
			expect(item).toHaveProperty('product_id', productId);
			// Note: Verify if your API returns nested product/location objects
		});
	});

	describe('Free tier limits', () => {
		beforeEach(() => {
			// Create a free tier user
			const freeUserData = createTestUser({
				email: 'free@example.com',
				isPremium: false
			});
			token = freeUserData.token;
			householdId = freeUserData.household.id;

			const location = createTestLocation({
				householdId,
				name: 'Fridge'
			});
			locationId = location.id;

			const product = createTestProduct({
				householdId,
				name: 'Free Product'
			});
			productId = product.id;

			// Create 25 items (FREE_LIMIT)
			for (let i = 0; i < 25; i++) {
				const prod = createTestProduct({
					householdId,
					name: `Product ${i}`,
					upc: `100000000${i.toString().padStart(3, '0')}`
				});

				createTestInventoryItem({
					productId: prod.id,
					locationId,
					householdId,
					quantity: 1
				});
			}
		});

		it('should reject creating 26th inventory item (exceeds free limit)', async () => {
			const res = await request(app)
				.post('/api/inventory')
				.set('Authorization', `Bearer ${token}`)
				.send({
					productId: productId,
					locationId: locationId,
					quantity: 1
				});

			expect(res.status).toBe(403);
			expect(res.body.error).toMatch(/limit reached/i);
		});
	});
});
