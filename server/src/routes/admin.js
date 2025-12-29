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
        const { isPremium } = req.body;
        
        if (typeof isPremium !== 'boolean') {
            return res.status(400).json({ error: 'isPremium must be a boolean' });
        }
        
        // Check household exists
        const household = db.prepare('SELECT id, name FROM households WHERE id = ?').get(householdId);
        if (!household) {
            return res.status(404).json({ error: 'Household not found' });
        }
        
        // Update premium status
        db.prepare('UPDATE households SET is_premium = ? WHERE id = ?')
            .run(isPremium ? 1 : 0, householdId);
        
        console.log(`[Admin] Updated household ${household.name} (${householdId}) premium status to: ${isPremium}`);
        
        res.json({
            householdId,
            name: household.name,
            isPremium
        });
    } catch (error) {
        console.error('Admin premium toggle error:', error);
        res.status(500).json({ error: 'Failed to update premium status' });
    }
});

module.exports = router;
