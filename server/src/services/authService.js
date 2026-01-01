const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const appleSignin = require('apple-signin-auth');
const logger = require('../utils/logger');

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

/**
 * Generate JWT token for user
 * @param {Object} user - User object with id, email, household_id
 * @returns {string} JWT token
 */
function generateToken(user) {
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
 * @param {string} email - User email
 * @param {string} password - User password
 * @param {string} firstName - User first name
 * @param {string} lastName - User last name
 * @returns {Object} { user, token }
 */
async function registerUser(email, password, firstName = '', lastName = '') {
    // Check if user exists
    const existingUser = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
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

    const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
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
 * @param {string} email - User email
 * @param {string} password - User password
 * @returns {Object} { user, token }
 */
async function loginUser(email, password) {
    const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
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
 * @param {string} identityToken - Apple identity token
 * @param {string} email - User email
 * @param {Object} name - User name { firstName, lastName }
 * @returns {Object} { user, token }
 */
async function appleSignIn(identityToken, email, name) {
    if (!identityToken) {
        throw new Error('Identity token is required');
    }

    // Verify identity token
    const { sub: appleId, email: appleEmail } = await appleSignin.verifyIdToken(identityToken, {});

    logger.logAuth('apple_signin_attempt', {
        appleId,
        appleEmail,
        inputEmail: email
    });

    // Check if user exists by Apple ID
    let user = db.prepare('SELECT * FROM users WHERE apple_id = ?').get(appleId);

    if (!user) {
        const searchEmail = email || appleEmail;
        // Check if user exists by email (linking accounts)
        const existingUser = db.prepare('SELECT * FROM users WHERE email = ?').get(searchEmail);
        if (existingUser) {
            logger.logAuth('apple_account_link', {
                appleId,
                userId: existingUser.id
            });
            db.prepare('UPDATE users SET apple_id = ? WHERE id = ?').run(appleId, existingUser.id);
            user = db.prepare('SELECT * FROM users WHERE id = ?').get(existingUser.id);
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

        user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
        
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
 * @param {string} userId - User ID
 * @returns {Object} { user, household, config }
 */
function getCurrentUser(userId) {
    const user = db.prepare('SELECT id, email, first_name, last_name, household_id FROM users WHERE id = ?').get(userId);
    if (!user) {
        throw new Error('User not found');
    }
    
    let household = null;
    if (user.household_id) {
        const h = db.prepare('SELECT id, name, is_premium, premium_expires_at, created_at FROM households WHERE id = ?').get(user.household_id);
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

module.exports = {
    generateToken,
    registerUser,
    loginUser,
    appleSignIn,
    getCurrentUser
};
