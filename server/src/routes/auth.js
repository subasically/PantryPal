const express = require('express');
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const { generateToken, authenticateToken } = require('../middleware/auth');
const appleSignin = require('apple-signin-auth');

const router = express.Router();

// Create default locations for a new household
function createDefaultLocations(householdId) {
    const now = new Date().toISOString();
    const defaultLocations = [
        { name: 'Basement Pantry', sortOrder: 0 },
        { name: 'Basement Chest Freezer', sortOrder: 1 },
        { name: 'Kitchen Fridge', sortOrder: 2 }
    ];

    for (const loc of defaultLocations) {
        const id = uuidv4();
        db.prepare(`
            INSERT INTO locations (id, household_id, name, parent_id, level, sort_order, created_at, updated_at)
            VALUES (?, ?, ?, NULL, 0, ?, ?, ?)
        `).run(id, householdId, loc.name, loc.sortOrder, now, now);
    }
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

        // Check if user exists by Apple ID
        let user = db.prepare('SELECT * FROM users WHERE apple_id = ?').get(appleId);

        // If not found by Apple ID, try email (linking accounts)
        if (!user && (email || appleEmail)) {
            const searchEmail = email || appleEmail;
            user = db.prepare('SELECT * FROM users WHERE email = ?').get(searchEmail);
            
            if (user) {
                // Link Apple ID to existing account
                db.prepare('UPDATE users SET apple_id = ? WHERE id = ?').run(appleId, user.id);
                user.apple_id = appleId;
            }
        }

        if (!user) {
            // Create new user
            const userId = uuidv4();
            const finalHouseholdId = uuidv4();
            
            // Create new household
            db.prepare('INSERT INTO households (id, name) VALUES (?, ?)').run(
                finalHouseholdId,
                householdName || `${name?.givenName || 'User'}'s Household`
            );
            
            createDefaultLocations(finalHouseholdId);

            // Create user
            // Note: password_hash is null for Apple-only users
            const userEmail = email || appleEmail || `${appleId}@privaterelay.appleid.com`;
            const userName = name ? `${name.givenName} ${name.familyName}`.trim() : 'Apple User';

            db.prepare(`
                INSERT INTO users (id, email, password_hash, name, household_id, apple_id)
                VALUES (?, ?, NULL, ?, ?, ?)
            `).run(userId, userEmail, userName, finalHouseholdId, appleId);

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
            token,
            householdId: user.household_id
        });

    } catch (error) {
        console.error('Apple Sign In error:', error);
        res.status(500).json({ error: 'Apple Sign In failed' });
    }
});

// Register new user
router.post('/register', async (req, res) => {
    try {
        const { email, password, name, householdName, householdId } = req.body;

        if (!email || !password || !name) {
            return res.status(400).json({ error: 'Email, password, and name are required' });
        }

        // Check if user already exists
        const existingUser = db.prepare('SELECT id FROM users WHERE email = ?').get(email);
        if (existingUser) {
            return res.status(409).json({ error: 'Email already registered' });
        }

        const passwordHash = await bcrypt.hash(password, 10);
        const userId = uuidv4();
        let finalHouseholdId = householdId;

        // If joining existing household
        if (householdId) {
            const household = db.prepare('SELECT id FROM households WHERE id = ?').get(householdId);
            if (!household) {
                return res.status(404).json({ error: 'Household not found' });
            }
        } else {
            // Create new household
            finalHouseholdId = uuidv4();
            db.prepare('INSERT INTO households (id, name) VALUES (?, ?)').run(
                finalHouseholdId,
                householdName || `${name}'s Household`
            );
            
            // Create default locations for the new household
            createDefaultLocations(finalHouseholdId);
        }

        // Create user
        db.prepare(`
            INSERT INTO users (id, email, password_hash, name, household_id)
            VALUES (?, ?, ?, ?, ?)
        `).run(userId, email, passwordHash, name, finalHouseholdId);

        const user = db.prepare('SELECT id, email, name, household_id FROM users WHERE id = ?').get(userId);
        const token = generateToken(user);

        res.status(201).json({
            user: {
                id: user.id,
                email: user.email,
                name: user.name,
                householdId: user.household_id
            },
            token,
            householdId: finalHouseholdId
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

// Get current user
router.get('/me', authenticateToken, (req, res) => {
    const user = db.prepare('SELECT id, email, name, household_id FROM users WHERE id = ?').get(req.user.id);
    if (!user) {
        return res.status(404).json({ error: 'User not found' });
    }
    
    const household = db.prepare('SELECT * FROM households WHERE id = ?').get(user.household_id);
    
    res.json({
        user: {
            id: user.id,
            email: user.email,
            name: user.name,
            householdId: user.household_id
        },
        household: household
    });
});

// Generate household invite code (6-character alphanumeric, expires in 24 hours)
router.post('/household/invite', authenticateToken, (req, res) => {
    try {
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
        
        const household = db.prepare('SELECT name FROM households WHERE id = ?').get(req.user.householdId);
        
        res.json({
            code,
            expiresAt,
            householdName: household?.name || 'Unknown Household'
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
