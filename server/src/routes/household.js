const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth');
const householdService = require('../services/householdService');

// Create a new household
router.post('/', authenticateToken, (req, res) => {
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
router.post('/invite', authenticateToken, (req, res) => {
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

// Validate invite code (for preview before joining) - NO AUTH REQUIRED
router.get('/invite/:code', (req, res) => {
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
router.post('/join', authenticateToken, (req, res) => {
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
router.get('/members', authenticateToken, (req, res) => {
    try {
        const members = householdService.getHouseholdMembers(req.user.householdId);
        res.json({ members });
    } catch (error) {
        console.error('Get members error:', error);
        res.status(500).json({ error: 'Failed to get household members' });
    }
});

// Get active invite codes for household
router.get('/invites', authenticateToken, (req, res) => {
    try {
        const invites = householdService.getActiveInviteCodes(req.user.householdId);
        res.json({ invites });
    } catch (error) {
        console.error('Get invites error:', error);
        res.status(500).json({ error: 'Failed to get invites' });
    }
});

// Reset household data (wipe inventory, history, custom products, locations)
router.delete('/data', authenticateToken, (req, res) => {
    try {
        console.log(`🗑️ [Household] DELETE /data - User ${req.user.id}, Household ${req.user.householdId}`);
        const result = householdService.resetHouseholdData(req.user.householdId, req.user.id);
        console.log(`✅ [Household] Household data reset completed successfully`);
        res.json(result);
    } catch (error) {
        console.error('❌ [Household] Reset household data error:', error);
        res.status(500).json({ error: 'Failed to reset household data' });
    }
});

module.exports = router;
