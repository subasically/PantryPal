const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth');
const authService = require('../services/authService');
const householdService = require('../services/householdService');

// Apple Sign In
router.post('/apple', async (req, res) => {
    try {
        const { identityToken, email, name } = req.body;
        const result = await authService.appleSignIn(identityToken, email, name);
        res.json(result);
    } catch (error) {
        console.error('Apple Sign In error:', error);
        res.status(500).json({ error: 'Apple Sign In failed' });
    }
});

// Register
router.post('/register', async (req, res) => {
    try {
        const { email, password, firstName, lastName, name } = req.body;

        // Validate required fields
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        // Support both new (firstName/lastName) and legacy (name) formats
        let finalFirstName = firstName || '';
        let finalLastName = lastName || '';

        if (name && !firstName && !lastName) {
            const nameParts = name.trim().split(/\s+/);
            finalFirstName = nameParts[0] || '';
            finalLastName = nameParts.slice(1).join(' ') || '';
        }

        const result = await authService.registerUser(email, password, finalFirstName, finalLastName);
        res.status(201).json({ ...result, householdId: null });
    } catch (error) {
        console.error('Registration error:', error);
        const status = error.message === 'User already exists' ? 400 : 500;
        res.status(status).json({ error: error.message || 'Registration failed' });
    }
});

// Login
router.post('/login', async (req, res) => {
    try {
        const { email, password } = req.body;

        // Validate required fields
        if (!email || !password) {
            return res.status(400).json({ error: 'Email and password are required' });
        }

        const result = await authService.loginUser(email, password);
        res.json(result);
    } catch (error) {
        console.error('Login error:', error);
        const status = error.message === 'Invalid credentials' ? 401 : 500;
        res.status(status).json({ error: error.message || 'Login failed' });
    }
});

const FREE_LIMIT = 25;

// Get current user
router.get('/me', authenticateToken, (req, res) => {
    try {
        const result = authService.getCurrentUser(req.user.id);
        res.json(result);
    } catch (error) {
        console.error('Get current user error:', error);
        res.status(404).json({ error: 'User not found' });
    }
});

// Create a new household
router.post('/household', authenticateToken, (req, res) => {
    try {
        const { name } = req.body;
        const result = householdService.createHousehold(req.user.id, name);
        res.status(201).json(result);
    } catch (error) {
        console.error('Create household error:', error);
        const status = error.message === 'User already belongs to a household' ? 400 : 500;
        res.status(status).json({ error: error.message || 'Failed to create household' });
    }
});

// Generate household invite code (6-character alphanumeric, expires in 24 hours)
router.post('/household/invite', authenticateToken, (req, res) => {
    try {
        const result = householdService.generateInviteCode(req.user.householdId, req.user.id);
        res.json(result);
    } catch (error) {
        console.error('Generate invite error:', error);
        if (error.code === 'PREMIUM_REQUIRED') {
            return res.status(403).json({
                error: error.message,
                code: 'PREMIUM_REQUIRED',
                upgradeRequired: true
            });
        }
        res.status(500).json({ error: 'Failed to generate invite code' });
    }
});

// Validate invite code (for preview before joining)
router.get('/household/invite/:code', (req, res) => {
    try {
        const { code } = req.params;
        const result = householdService.validateInviteCode(code);
        res.json(result);
    } catch (error) {
        console.error('Validate invite error:', error);
        res.status(404).json({ error: error.message || 'Invalid or expired invite code' });
    }
});

// Join household with invite code
router.post('/household/join', authenticateToken, (req, res) => {
    try {
        const { code } = req.body;

        if (!code) {
            return res.status(400).json({ error: 'Invite code is required' });
        }

        const result = householdService.joinHousehold(req.user.id, code);
        res.json(result);
    } catch (error) {
        console.error('Join household error:', error);
        res.status(404).json({ error: error.message || 'Failed to join household' });
    }
});

// Get household members
router.get('/household/members', authenticateToken, (req, res) => {
    try {
        const members = householdService.getHouseholdMembers(req.user.householdId);
        res.json({ members });
    } catch (error) {
        console.error('Get members error:', error);
        res.status(500).json({ error: 'Failed to get household members' });
    }
});

// Get active invite codes for household
router.get('/household/invites', authenticateToken, (req, res) => {
    try {
        const invites = householdService.getActiveInviteCodes(req.user.householdId);
        res.json({ invites });
    } catch (error) {
        console.error('Get invites error:', error);
        res.status(500).json({ error: 'Failed to get invites' });
    }
});

// Reset household data (wipe inventory, history, custom products, locations)
router.delete('/household/data', authenticateToken, (req, res) => {
    try {
        console.log(`🗑️ [Auth] DELETE /household/data - User ${req.user.id}, Household ${req.user.householdId}`);
        const result = householdService.resetHouseholdData(req.user.householdId, req.user.id);
        console.log(`✅ [Auth] Household data reset completed successfully`);
        res.json(result);
    } catch (error) {
        console.error('❌ [Auth] Reset household data error:', error);
        res.status(500).json({ error: 'Failed to reset household data' });
    }
});

module.exports = router;
