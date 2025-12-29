const express = require('express');
const router = express.Router();
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const appleSignin = require('apple-signin-auth');
const authenticateToken = require('../middleware/auth');

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

// Helper to generate JWT
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

// Helper to create default locations
function createDefaultLocations(householdId) {
    const defaultLocations = [
        { name: 'Pantry', sortOrder: 0 },
        { name: 'Fridge', sortOrder: 1 },
        { name: 'Freezer', sortOrder: 2 },
        { name: 'Other', sortOrder: 3 }
    ];
    
    const insertLocation = db.prepare(`
        INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
        VALUES (?, ?, ?, NULL, 0, ?, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
    `);
    
    defaultLocations.forEach(loc => {
        insertLocation.run(uuidv4(), householdId, loc.name, loc.sortOrder);
    });
}

// Apple Sign In
router.post('/apple', async (req, res) => {
    try {
        const { identityToken, email, name, householdName } = req.body;

        if (!identityToken) {
            return res.status(400).json({ error: 'Identity token is required' });
        }

        // Verify identity token
        const { sub: appleId, email: appleEmail } = await appleSignin.verifyIdToken(identityToken, {
            // Optional: audience: 'com.your.app.bundle.id',
            // Optional: ignoreExpiration: true, // Ignore token expiration
        });

        console.log(`[Auth] Apple Sign In attempt: AppleID=${appleId}, Email=${appleEmail}, InputEmail=${email}`);

        // Check if user exists by Apple ID
        let user = db.prepare('SELECT * FROM users WHERE apple_id = ?').get(appleId);

        if (!user) {
             const searchEmail = email || appleEmail;
             // Check if user exists by email (linking accounts)
             const existingUser = db.prepare('SELECT * FROM users WHERE email = ?').get(searchEmail);
             if (existingUser) {
                 console.log('[Auth] Linking Apple ID ' + appleId + ' to existing user ' + existingUser.id);
                 db.prepare('UPDATE users SET apple_id = ? WHERE id = ?').run(appleId, existingUser.id);
                 user = db.prepare('SELECT * FROM users WHERE id = ?').get(existingUser.id);
             }
        }

        if (!user) {
            // Create new user
            const userId = uuidv4();
            // Household will be created later via /household/create
            // let householdId = null; 

            const finalEmail = email || appleEmail || `${appleId}@privaterelay.appleid.com`;
            
            let finalName = 'Apple User';
            if (name) {
                // Handle both raw object and PersonNameComponents (givenName/familyName)
                const first = name.firstName || name.givenName || '';
                const last = name.lastName || name.familyName || '';
                if (first || last) {
                    finalName = `${first} ${last}`.trim();
                }
            }

            // Create user with placeholder password hash (since they use Apple Sign In)
            // We use a dummy hash that won't match any password
            const placeholderHash = '$2a$10$placeholder_hash_for_apple_signin_users_only';

            db.prepare(`
                INSERT INTO users (id, email, password_hash, name, household_id, apple_id)
                VALUES (?, ?, ?, ?, NULL, ?)
            `).run(userId, finalEmail, placeholderHash, finalName, appleId);

            user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
        }

        const token = generateToken(user);

        res.json({
            user: {
                id: user.id,
                email: user.email,
                name: user.name,
                householdId: user.household_id
            },
            token
        });
    } catch (error) {
        console.error('Apple Sign In error:', error);
        res.status(500).json({ error: 'Apple Sign In failed' });
    }
});

// Register
router.post('/register', async (req, res) => {
    try {
        const { email, password, name, householdName } = req.body;

        if (!email || !password || !name) {
            return res.status(400).json({ error: 'Email, password, and name are required' });
        }

        // Check if user exists
        const existingUser = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
        if (existingUser) {
            return res.status(400).json({ error: 'User already exists' });
        }

        const hashedPassword = await bcrypt.hash(password, 10);
        const userId = uuidv4();
        
        // Household will be created later
        // let finalHouseholdId = null;

        // Create user
        db.prepare(`
            INSERT INTO users (id, email, password_hash, name, household_id)
            VALUES (?, ?, ?, ?, NULL)
        `).run(userId, email, hashedPassword, name);

        const user = db.prepare('SELECT * FROM users WHERE id = ?').get(userId);
        const token = generateToken(user);

        res.status(201).json({
            user: {
                id: user.id,
                email: user.email,
                name: user.name,
                householdId: null
            },
            token,
            householdId: null
        });
    } catch (error) {
        console.error('Registration error:', error);
        res.status(500).json({ error: 'Registration failed' });
    }
});

// Login
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        const user = db.prepare('SELECT * FROM users WHERE email = ?').get(email);
        if (!user) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        const validPassword = await bcrypt.compare(password, user.password_hash);
        if (!validPassword) {
            return res.status(401).json({ error: 'Invalid credentials' });
        }

        const token = generateToken(user);

        res.json({
            user: {
                id: user.id,
                email: user.email,
                name: user.name,
                householdId: user.household_id
            },
            token
        });
    } catch (error) {
        console.error('Login error:', error);
        res.status(500).json({ error: 'Login failed' });
    }
});

const FREE_LIMIT = 30;

// Get current user
router.get('/me', authenticateToken, (req, res) => {
    const user = db.prepare('SELECT id, email, name, household_id FROM users WHERE id = ?').get(req.user.id);
    if (!user) {
        return res.status(404).json({ error: 'User not found' });
    }
    
    let household = null;
    if (user.household_id) {
        const h = db.prepare('SELECT * FROM households WHERE id = ?').get(user.household_id);
        if (h) {
            household = {
                ...h,
                isPremium: Boolean(h.is_premium)
            };
        }
    }
    
    res.json({
        user: {
            id: user.id,
            email: user.email,
            name: user.name,
            householdId: user.household_id
        },
        household,
        config: {
            freeLimit: FREE_LIMIT
        }
    });
});

// Create a new household
router.post('/household', authenticateToken, (req, res) => {
    try {
        const { name } = req.body;
        
        // Check if user already has a household
        if (req.user.householdId) {
            return res.status(400).json({ error: 'User already belongs to a household' });
        }

        const householdId = uuidv4();
        const householdName = name || 'My Household';
        
        const transaction = db.transaction(() => {
            // Create household
            db.prepare('INSERT INTO households (id, name) VALUES (?, ?)').run(householdId, householdName);
            
            // Update user
            db.prepare('UPDATE users SET household_id = ? WHERE id = ?').run(householdId, req.user.id);
            
            // Create default locations
            createDefaultLocations(householdId);
        });
        
        transaction();
        
        res.status(201).json({
            id: householdId,
            name: householdName,
            isPremium: false
        });
    } catch (error) {
        console.error('Create household error:', error);
        res.status(500).json({ error: 'Failed to create household' });
    }
});

// Generate household invite code (6-character alphanumeric, expires in 24 hours)
router.post('/household/invite', authenticateToken, (req, res) => {
    try {
        // Check if household is premium
        const household = db.prepare('SELECT is_premium FROM households WHERE id = ?').get(req.user.householdId);
        if (!household.is_premium) {
            return res.status(403).json({ 
                error: 'Household sharing is a Premium feature',
                code: 'PREMIUM_REQUIRED',
                upgradeRequired: true
            });
        }

        // Generate a 6-character alphanumeric code
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude confusing chars (0,O,1,I)
        let code = '';
        for (let i = 0; i < 6; i++) {
            code += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        
        const id = uuidv4();
        const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(); // 24 hours
        
        db.prepare(`
            INSERT INTO invite_codes (id, household_id, code, created_by, expires_at)
            VALUES (?, ?, ?, ?, ?)
        `).run(id, req.user.householdId, code, req.user.id, expiresAt);
        
        const householdName = db.prepare('SELECT name FROM households WHERE id = ?').get(req.user.householdId);
        
        res.json({
            code,
            expiresAt,
            householdName: householdName?.name || 'Unknown Household'
        });
    } catch (error) {
        console.error('Generate invite error:', error);
        res.status(500).json({ error: 'Failed to generate invite code' });
    }
});

// Validate invite code (for preview before joining)
router.get('/household/invite/:code', (req, res) => {
    try {
        const { code } = req.params;
        
        const invite = db.prepare(`
            SELECT ic.*, h.name as household_name
            FROM invite_codes ic
            JOIN households h ON ic.household_id = h.id
            WHERE ic.code = ? AND ic.used_by IS NULL AND ic.expires_at > datetime('now')
        `).get(code.toUpperCase());
        
        if (!invite) {
            return res.status(404).json({ error: 'Invalid or expired invite code' });
        }
        
        // Count household members
        const memberCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE household_id = ?').get(invite.household_id);
        
        res.json({
            valid: true,
            householdId: invite.household_id,
            householdName: invite.household_name,
            memberCount: memberCount.count,
            expiresAt: invite.expires_at
        });
    } catch (error) {
        console.error('Validate invite error:', error);
        res.status(500).json({ error: 'Failed to validate invite code' });
    }
});

// Join household with invite code
router.post('/household/join', authenticateToken, (req, res) => {
    try {
        const { code } = req.body;
        
        if (!code) {
            return res.status(400).json({ error: 'Invite code is required' });
        }
        
        const invite = db.prepare(`
            SELECT * FROM invite_codes
            WHERE code = ? AND used_by IS NULL AND expires_at > datetime('now')
        `).get(code.toUpperCase());
        
        if (!invite) {
            return res.status(404).json({ error: 'Invalid or expired invite code' });
        }
        
        // Update user's household
        db.prepare('UPDATE users SET household_id = ?, updated_at = ? WHERE id = ?')
            .run(invite.household_id, new Date().toISOString(), req.user.id);
        
        // Mark invite as used
        db.prepare('UPDATE invite_codes SET used_by = ?, used_at = ? WHERE id = ?')
            .run(req.user.id, new Date().toISOString(), invite.id);
        
        const household = db.prepare('SELECT * FROM households WHERE id = ?').get(invite.household_id);
        
        res.json({
            success: true,
            household: {
                id: household.id,
                name: household.name
            }
        });
    } catch (error) {
        console.error('Join household error:', error);
        res.status(500).json({ error: 'Failed to join household' });
    }
});

// Get household members
router.get('/household/members', authenticateToken, (req, res) => {
    try {
        const members = db.prepare(`
            SELECT id, email, name, created_at
            FROM users
            WHERE household_id = ?
            ORDER BY created_at ASC
        `).all(req.user.householdId);
        
        res.json({ members });
    } catch (error) {
        console.error('Get members error:', error);
        res.status(500).json({ error: 'Failed to get household members' });
    }
});

// Get active invite codes for household
router.get('/household/invites', authenticateToken, (req, res) => {
    try {
        const invites = db.prepare(`
            SELECT code, expires_at, created_at
            FROM invite_codes
            WHERE household_id = ? AND used_by IS NULL AND expires_at > datetime('now')
            ORDER BY created_at DESC
        `).all(req.user.householdId);
        
        res.json({ invites });
    } catch (error) {
        console.error('Get invites error:', error);
        res.status(500).json({ error: 'Failed to get invites' });
    }
});

// Reset household data (wipe inventory, history, custom products, locations)
router.delete('/household/data', authenticateToken, (req, res) => {
    try {
        const householdId = req.user.householdId;
        console.log(`[Reset] Wiping data for household ${householdId} by user ${req.user.id}`);

        const deleteInventory = db.prepare('DELETE FROM inventory WHERE household_id = ?');
        const deleteHistory = db.prepare('DELETE FROM checkout_history WHERE household_id = ?');
        const deleteCustomProducts = db.prepare('DELETE FROM products WHERE household_id = ? AND is_custom = 1');
        const deleteLocations = db.prepare('DELETE FROM locations WHERE household_id = ?');

        const transaction = db.transaction(() => {
            deleteInventory.run(householdId);
            deleteHistory.run(householdId);
            deleteCustomProducts.run(householdId);
            deleteLocations.run(householdId);
            
            // Re-seed default locations so the app isn't empty
            createDefaultLocations(householdId);
        });

        transaction();

        res.json({ success: true, message: 'Household data reset successfully' });
    } catch (error) {
        console.error('Reset household data error:', error);
        res.status(500).json({ error: 'Failed to reset household data' });
    }
});

module.exports = router;
