const jwt = require('jsonwebtoken');
const db = require('../models/database');
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.sendStatus(401);
    }

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) {
            return res.sendStatus(403);
        }
        
        try {
            // Fetch fresh user data to ensure householdId is up to date
            const freshUser = db.prepare('SELECT * FROM users WHERE id = ?').get(user.id);
            
            if (!freshUser) {
                return res.sendStatus(403);
            }
            
            req.user = {
                id: freshUser.id,
                email: freshUser.email,
                name: freshUser.name,
                householdId: freshUser.household_id
            };
            
            next();
        } catch (error) {
            console.error('Auth middleware error:', error);
            res.sendStatus(500);
        }
    });
}

module.exports = authenticateToken;
