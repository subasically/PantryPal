const jwt = require('jsonwebtoken');
const db = require('../models/database');
const logger = require('../utils/logger');
const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key';

function authenticateToken(req, res, next) {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        logger.logAuth('token_missing', {
            path: req.path,
            ip: req.ip
        });
        return res.sendStatus(401);
    }

    jwt.verify(token, JWT_SECRET, (err, user) => {
        if (err) {
            logger.logAuth('token_invalid', {
                error: err.message,
                path: req.path,
                ip: req.ip
            });
            return res.sendStatus(403);
        }
        
        try {
            // Fetch fresh user data to ensure householdId is up to date
            const freshUser = db.prepare('SELECT * FROM users WHERE id = ?').get(user.id);
            
            if (!freshUser) {
                logger.logAuth('user_not_found', {
                    userId: user.id,
                    path: req.path
                });
                return res.sendStatus(403);
            }
            
            req.user = {
                id: freshUser.id,
                email: freshUser.email,
                name: freshUser.name,
                householdId: freshUser.household_id
            };
            
            logger.logAuth('token_validated', {
                userId: freshUser.id,
                householdId: freshUser.household_id,
                path: req.path
            });
            
            next();
        } catch (error) {
            logger.logError('Auth middleware error', error, {
                userId: user?.id,
                path: req.path
            });
            res.sendStatus(500);
        }
    });
}

module.exports = authenticateToken;
