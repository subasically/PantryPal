/**
 * Shared test helpers and fixtures
 */

import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { getTestDb } from './testDb';
import { logSync } from '../services/syncLogger';

const JWT_SECRET = process.env.JWT_SECRET || 'test-secret-key';

interface CreateTestUserOptions {
	userId?: string;
	email?: string;
	password?: string;
	householdId?: string;
	householdName?: string;
	createHousehold?: boolean;
	isPremium?: boolean;
	premiumExpiresAt?: string;
}

interface TestUser {
	id: string;
	email: string;
	password: string;
	householdId: string | null;
}

interface TestHousehold {
	id: string;
	name: string;
	ownerId: string;
	inviteCode: string;
	isPremium: boolean;
	premiumExpiresAt?: string;
}

interface TestUserResult {
	user: TestUser;
	household: TestHousehold | null;
	token: string;
}

/**
 * Creates a test user with household
 */
export function createTestUser(options: CreateTestUserOptions = {}): TestUserResult {
	const db = getTestDb();

	const userId = options.userId || uuidv4();
	const email = options.email || `test-${Date.now()}@example.com`;
	const password = options.password || 'password123';
	const hashedPassword = bcrypt.hashSync(password, 10);

	// Create user
	db.prepare(`
        INSERT INTO users (id, email, password_hash, created_at)
        VALUES (?, ?, ?, datetime('now'))
    `).run(userId, email, hashedPassword);

	// Create household if needed
	let householdId = options.householdId;
	let household: TestHousehold | null = null;

	if (options.createHousehold !== false) {
		householdId = householdId || uuidv4();
		const householdName = options.householdName || `Test Household ${Date.now()}`;
		const inviteCode = generateInviteCode();

		db.prepare(`
            INSERT INTO households (id, name, owner_id, invite_code, created_at)
            VALUES (?, ?, ?, ?, datetime('now'))
        `).run(householdId, householdName, userId, inviteCode);

		// Update user with household
		db.prepare('UPDATE users SET household_id = ? WHERE id = ?')
			.run(householdId, userId);

		household = {
			id: householdId,
			name: householdName,
			ownerId: userId,
			inviteCode,
			isPremium: options.isPremium || false
		};

		// Set premium if requested
		if (options.isPremium) {
			const expiresAt = options.premiumExpiresAt || new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString();
			db.prepare('UPDATE households SET is_premium = 1, premium_expires_at = ? WHERE id = ?')
				.run(expiresAt, householdId);
			household.premiumExpiresAt = expiresAt;
		}
	}

	// Generate JWT token
	const token = jwt.sign(
		{ id: userId, email, householdId },
		JWT_SECRET,
		{ expiresIn: '7d' }
	);

	const user: TestUser = {
		id: userId,
		email,
		password, // Plain password for testing
		householdId: householdId || null
	};

	return { user, household, token };
}

interface CreateTestProductOptions {
	id?: string;
	name?: string;
	upc?: string | null;
	brand?: string | null;
	category?: string | null;
	isCustom?: boolean;
	householdId?: string | null;
}

interface TestProduct {
	id: string;
	upc: string | null;
	name: string;
	brand: string | null;
	category: string | null;
	isCustom: boolean;
	householdId: string | null;
}

/**
 * Creates a test product
 */
export function createTestProduct(options: CreateTestProductOptions = {}): TestProduct {
	const db = getTestDb();

	const productId = options.id || uuidv4();
	const name = options.name || `Test Product ${Date.now()}`;
	const upc = options.upc || null;
	const brand = options.brand || null;
	const category = options.category || null;
	const isCustom = options.isCustom !== undefined ? (options.isCustom ? 1 : 0) : 1;
	const householdId = options.householdId || null;

	db.prepare(`
        INSERT INTO products (id, upc, name, brand, category, is_custom, household_id, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, datetime('now'))
    `).run(productId, upc, name, brand, category, isCustom, householdId);

	// Log sync event if household exists
	if (householdId) {
		logSync(householdId, 'product', productId, 'create', {
			name, brand, category, upc
		});
	}

	return {
		id: productId,
		upc,
		name,
		brand,
		category,
		isCustom: Boolean(isCustom),
		householdId
	};
}

interface CreateTestLocationOptions {
	id?: string;
	householdId: string;
	name?: string;
	type?: string;
}

interface TestLocation {
	id: string;
	householdId: string;
	name: string;
	type: string;
}

/**
 * Creates a test location
 */
export function createTestLocation(options: CreateTestLocationOptions): TestLocation {
	const db = getTestDb();

	if (!options.householdId) {
		throw new Error('householdId is required for createTestLocation');
	}

	const locationId = options.id || uuidv4();
	const name = options.name || `Test Location ${Date.now()}`;
	const type = options.type || 'pantry';

	db.prepare(`
        INSERT INTO locations (id, household_id, name, type, created_at)
        VALUES (?, ?, ?, ?, datetime('now'))
    `).run(locationId, options.householdId, name, type);

	// Log sync event
	logSync(options.householdId, 'location', locationId, 'create', {
		name, type
	});

	return {
		id: locationId,
		householdId: options.householdId,
		name,
		type
	};
}

interface CreateTestInventoryItemOptions {
	id?: string;
	householdId: string;
	productId: string;
	locationId: string;
	quantity?: number;
	unit?: string;
	expirationDate?: string | null;
	notes?: string | null;
}

interface TestInventoryItem {
	id: string;
	householdId: string;
	productId: string;
	locationId: string;
	quantity: number;
	unit: string;
	expirationDate: string | null;
	notes: string | null;
}

/**
 * Creates a test inventory item
 */
export function createTestInventoryItem(options: CreateTestInventoryItemOptions): TestInventoryItem {
	const db = getTestDb();

	if (!options.productId || !options.locationId || !options.householdId) {
		throw new Error('productId, locationId, and householdId are required');
	}

	const itemId = options.id || uuidv4();
	const quantity = options.quantity !== undefined ? options.quantity : 1;
	const unit = options.unit || 'pcs';
	const expirationDate = options.expirationDate || null;
	const notes = options.notes || null;

	db.prepare(`
        INSERT INTO inventory (id, household_id, product_id, location_id, quantity, unit, expiration_date, notes, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
    `).run(itemId, options.householdId, options.productId, options.locationId, quantity, unit, expirationDate, notes);

	// Log sync event
	logSync(options.householdId, 'inventory', itemId, 'create', {
		productId: options.productId,
		locationId: options.locationId,
		quantity,
		unit,
		expirationDate
	});

	return {
		id: itemId,
		householdId: options.householdId,
		productId: options.productId,
		locationId: options.locationId,
		quantity,
		unit,
		expirationDate,
		notes
	};
}

/**
 * Generates a random 6-character invite code
 */
export function generateInviteCode(): string {
	return Math.random().toString(36).substring(2, 8).toUpperCase();
}

/**
 * Waits for a specified duration
 * @param ms - Milliseconds to wait
 */
export function delay(ms: number): Promise<void> {
	return new Promise(resolve => setTimeout(resolve, ms));
}
