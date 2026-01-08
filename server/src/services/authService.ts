import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import appleSignin from 'apple-signin-auth';
import logger from '../utils/logger';
import db from '../models/database';

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

// Use imported database directly
function getDb() {
	return db;
}

interface UserRow {
	id: string;
	email: string;
	password_hash: string;
	first_name: string | null;
	last_name: string | null;
	household_id: string | null;
	apple_id: string | null;
}

interface HouseholdRow {
	id: string;
	name: string;
	is_premium: number;
	premium_expires_at: string | null;
	created_at: string;
}

export interface UserResponse {
	id: string;
	email: string;
	firstName: string;
	lastName: string;
	householdId: string | null;
}

export interface AuthResponse {
	user: UserResponse;
	token: string;
}

export interface HouseholdInfo {
	id: string;
	name: string;
	isPremium: boolean;
	premiumExpiresAt: string | null;
	createdAt: string;
}

export interface CurrentUserResponse {
	user: UserResponse;
	household: HouseholdInfo | null;
	config: {
		freeLimit: number;
	};
}

interface AppleIdTokenPayload {
	sub: string;
	email?: string;
}

interface AppleName {
	firstName?: string;
	lastName?: string;
	givenName?: string;
	familyName?: string;
}

/**
 * Generate JWT token for user
 * @param user - User object with id, email, household_id
 * @returns JWT token
 */
function generateToken(user: UserRow): string {
	return jwt.sign(
		{
			id: user.id,
			email: user.email,
			householdId: user.household_id
		},
		JWT_SECRET,
		{ expiresIn: '30d' }
	);
}

/**
 * Register a new user with email/password
 * @param email - User email
 * @param password - User password
 * @param firstName - User first name
 * @param lastName - User last name
 * @returns { user, token }
 */
async function registerUser(
	email: string,
	password: string,
	firstName: string = '',
	lastName: string = ''
): Promise<AuthResponse> {
	const db = getDb();

	// Check if user exists
	const existingUser = db.prepare('SELECT * FROM users WHERE email = ?').get(email) as UserRow | undefined;
	if (existingUser) {
		logger.logAuth('register_failed', {
			email,
			reason: 'user_already_exists'
		});
		throw new Error('User already exists');
	}

	const hashedPassword = await bcrypt.hash(password, 10);
	const userId = uuidv4();

	// Create user
	db.prepare(`
        INSERT INTO users (id, email, password_hash, first_name, last_name, household_id)
        VALUES (?, ?, ?, ?, ?, NULL)
    `).run(userId, email, hashedPassword, firstName, lastName);

	const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as UserRow;
	const token = generateToken(user);

	logger.logAuth('register_success', {
		userId,
		email
	});

	return {
		user: {
			id: user.id,
			email: user.email,
			firstName: user.first_name || '',
			lastName: user.last_name || '',
			householdId: null
		},
		token
	};
}

/**
 * Login user with email/password
 * @param email - User email
 * @param password - User password
 * @returns { user, token }
 */
async function loginUser(email: string, password: string): Promise<AuthResponse> {
	const db = getDb();

	const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email) as UserRow | undefined;
	if (!user) {
		logger.logAuth('login_failed', {
			email,
			reason: 'user_not_found'
		});
		throw new Error('Invalid credentials');
	}

	const validPassword = await bcrypt.compare(password, user.password_hash);
	if (!validPassword) {
		logger.logAuth('login_failed', {
			email,
			userId: user.id,
			reason: 'invalid_password'
		});
		throw new Error('Invalid credentials');
	}

	const token = generateToken(user);

	logger.logAuth('login_success', {
		userId: user.id,
		email,
		householdId: user.household_id
	});

	return {
		user: {
			id: user.id,
			email: user.email,
			firstName: user.first_name || '',
			lastName: user.last_name || '',
			householdId: user.household_id
		},
		token
	};
}

/**
 * Authenticate user with Apple Sign In
 * @param identityToken - Apple identity token
 * @param email - User email
 * @param name - User name { firstName, lastName }
 * @returns { user, token }
 */
async function appleSignIn(
	identityToken: string,
	email?: string,
	name?: AppleName
): Promise<AuthResponse> {
	const db = getDb();

	if (!identityToken) {
		throw new Error('Identity token is required');
	}

	// Verify identity token
	const payload = await appleSignin.verifyIdToken(identityToken, {}) as AppleIdTokenPayload;
	const { sub: appleId, email: appleEmail } = payload;

	logger.logAuth('apple_signin_attempt', {
		appleId,
		appleEmail,
		inputEmail: email
	});

	// Check if user exists by Apple ID
	let user = db.prepare('SELECT * FROM users WHERE apple_id = ?').get(appleId) as UserRow | undefined;

	if (!user) {
		const searchEmail = email || appleEmail;
		// Check if user exists by email (linking accounts)
		const existingUser = db.prepare('SELECT * FROM users WHERE email = ?').get(searchEmail) as UserRow | undefined;
		if (existingUser) {
			logger.logAuth('apple_account_link', {
				appleId,
				userId: existingUser.id
			});
			db.prepare('UPDATE users SET apple_id = ? WHERE id = ?').run(appleId, existingUser.id);
			user = db.prepare('SELECT * FROM users WHERE id = ?').get(existingUser.id) as UserRow;
		}
	}

	if (!user) {
		// Create new user
		const userId = uuidv4();
		const finalEmail = email || appleEmail || `${appleId}@privaterelay.appleid.com`;
		const placeholderHash = '$2a$10$placeholder_hash_for_apple_signin_users_only';

		const firstName = name?.firstName || name?.givenName || '';
		const lastName = name?.lastName || name?.familyName || '';

		db.prepare(`
            INSERT INTO users (id, email, password_hash, first_name, last_name, household_id, apple_id)
            VALUES (?, ?, ?, ?, ?, NULL, ?)
        `).run(userId, finalEmail, placeholderHash, firstName, lastName, appleId);

		user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId) as UserRow;

		logger.logAuth('apple_user_created', {
			userId,
			email: finalEmail,
			appleId
		});
	}

	const token = generateToken(user);

	logger.logAuth('apple_signin_success', {
		userId: user.id,
		householdId: user.household_id
	});

	return {
		user: {
			id: user.id,
			email: user.email,
			firstName: user.first_name || '',
			lastName: user.last_name || '',
			householdId: user.household_id
		},
		token
	};
}

/**
 * Get current user details
 * @param userId - User ID
 * @returns { user, household, config }
 */
function getCurrentUser(userId: string): CurrentUserResponse {
	const db = getDb();

	const user = db.prepare('SELECT id, email, first_name, last_name, household_id FROM users WHERE id = ?')
		.get(userId) as UserRow | undefined;

	if (!user) {
		throw new Error('User not found');
	}

	let household: HouseholdInfo | null = null;
	if (user.household_id) {
		const h = db.prepare('SELECT id, name, is_premium, premium_expires_at, created_at FROM households WHERE id = ?')
			.get(user.household_id) as HouseholdRow | undefined;

		if (h) {
			household = {
				id: h.id,
				name: h.name,
				isPremium: Boolean(h.is_premium),
				premiumExpiresAt: h.premium_expires_at,
				createdAt: h.created_at
			};
		}
	}

	return {
		user: {
			id: user.id,
			email: user.email,
			firstName: user.first_name || '',
			lastName: user.last_name || '',
			householdId: user.household_id
		},
		household,
		config: {
			freeLimit: 25
		}
	};
}

export default {
	generateToken,
	registerUser,
	loginUser,
	appleSignIn,
	getCurrentUser
};
