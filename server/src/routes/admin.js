const express = require('express');
const router = express.Router();
const db = require('../models/database');

// Admin authentication middleware
function adminAuth(req, res, next) {
    const adminKey = req.headers['x-admin-key'];
    const expectedKey = process.env.ADMIN_KEY;

    if (!expectedKey) {
        return res.status(503).json({ error: 'Admin routes not properly configured' });
    }

    if (!adminKey || adminKey !== expectedKey) {
        return res.status(401).json({ error: 'Unauthorized - Invalid admin key' });
    }

    next();
}

// Toggle Premium for household (DEV/TEST ONLY)
router.post('/households/:householdId/premium', adminAuth, (req, res) => {
    try {
        const { householdId } = req.params;
        const { isPremium, expiresAt } = req.body;

        if (typeof isPremium !== 'boolean') {
            return res.status(400).json({ error: 'isPremium must be a boolean' });
        }

        // Check household exists
        const household = db.prepare('SELECT id, name FROM households WHERE id = ?').get(householdId);
        if (!household) {
            return res.status(404).json({ error: 'Household not found' });
        }

        // Update premium status
        // If isPremium is true and expiresAt is provided, set it
        // If isPremium is true and expiresAt is not provided, set to NULL (no expiration)
        // If isPremium is false, clear expiration
        const premiumExpiresAt = isPremium && expiresAt ? expiresAt : null;

        db.prepare('UPDATE households SET is_premium = ?, premium_expires_at = ? WHERE id = ?')
            .run(isPremium ? 1 : 0, premiumExpiresAt, householdId);

        console.log(`[Admin] Updated household ${household.name} (${householdId}) premium status to: ${isPremium}, expires: ${premiumExpiresAt || 'never'}`);

        res.json({
            householdId,
            name: household.name,
            isPremium,
            premiumExpiresAt
        });
    } catch (error) {
        console.error('Admin premium toggle error:', error);
        res.status(500).json({ error: 'Failed to update premium status' });
    }
});

// Remove Premium from household by email (DEV/TEST ONLY)
router.post('/remove-premium', adminAuth, (req, res) => {
    try {
        const { email } = req.body;

        if (!email) {
            return res.status(400).json({ error: 'email is required' });
        }

        // Find user by email
        const user = db.prepare('SELECT id, email, household_id FROM users WHERE email = ?').get(email);
        if (!user) {
            return res.status(404).json({ error: 'User not found' });
        }

        if (!user.household_id) {
            return res.status(400).json({ error: 'User has no household' });
        }

        // Remove premium from household
        db.prepare('UPDATE households SET is_premium = 0, premium_expires_at = NULL WHERE id = ?')
            .run(user.household_id);

        const household = db.prepare('SELECT name FROM households WHERE id = ?').get(user.household_id);

        console.log(`[Admin] Removed Premium from ${email}'s household (${household.name})`);

        res.json({
            success: true,
            message: `Premium removed from ${email}'s household`,
            householdId: user.household_id,
            householdName: household.name
        });
    } catch (error) {
        console.error('Admin remove premium error:', error);
        res.status(500).json({ error: 'Failed to remove premium' });
    }
});

module.exports = router;
