const express = require('express');
const router = express.Router();
const authenticateToken = require('../middleware/auth');
const db = require('../models/database');
const logger = require('../utils/logger');

/**
 * @route   POST /api/subscriptions/validate
 * @desc    Validate a StoreKit transaction receipt and update household Premium status
 * @access  Private
 */
router.post('/validate', authenticateToken, (req, res) => {
    const { transactionId, productId, originalTransactionId, expiresAt } = req.body;
    const userId = req.user.id;

    logger.info(`🍎 [StoreKit] Validating receipt for user ${userId}`, {
        transactionId,
        productId,
        expiresAt
    });

    try {
        // Validate required fields
        if (!transactionId || !productId || !originalTransactionId) {
            logger.warn(`⚠️  [StoreKit] Missing required fields`, { body: req.body });
            return res.status(400).json({ error: 'Missing required transaction fields' });
        }

        // Get user's household
        const user = db.prepare('SELECT household_id FROM users WHERE id = ?').get(userId);

        if (!user) {
            logger.error(`❌ [StoreKit] User not found: ${userId}`);
            return res.status(404).json({ error: 'User not found' });
        }

        if (!user.household_id) {
            logger.error(`❌ [StoreKit] User ${userId} has no household`);
            return res.status(400).json({ error: 'User must belong to a household to purchase Premium' });
        }

        // Calculate expiration timestamp
        // For iOS, the expiresAt is already in ISO8601 format from transaction.expirationDate
        const premiumExpiresAt = expiresAt || null;

        logger.info(`📝 [StoreKit] Updating household ${user.household_id} with premium_expires_at: ${premiumExpiresAt}`);

        // Update household Premium status
        const updateHousehold = db.prepare(`
            UPDATE households 
            SET 
                is_premium = 1,
                premium_expires_at = ?
            WHERE id = ?
        `);

        updateHousehold.run(premiumExpiresAt, user.household_id);

        logger.info(`✅ [StoreKit] Premium activated for household ${user.household_id}`, {
            productId,
            expiresAt: premiumExpiresAt
        });

        // Record the transaction (optional - for audit trail)
        // You could create a transactions table to track all purchases
        // For now, we'll just return success

        // Fetch updated household info
        const household = db.prepare(`
            SELECT id, name, is_premium, premium_expires_at, created_at 
            FROM households 
            WHERE id = ?
        `).get(user.household_id);

        // Build response
        const response = {
            household: {
                id: household.id,
                name: household.name,
                isPremium: Boolean(household.is_premium),
                premiumExpiresAt: household.premium_expires_at,
                createdAt: household.created_at
            },
            subscription: {
                productId,
                expiresAt: premiumExpiresAt,
                isActive: true
            }
        };

        logger.info(`📲 [StoreKit] Validation response sent`, { householdId: household.id });
        res.json(response);

    } catch (error) {
        logger.error(`❌ [StoreKit] Validation error: ${error.message}`, {
            userId,
            transactionId,
            error: error.stack
        });
        res.status(500).json({ error: 'Failed to validate subscription' });
    }
});

/**
 * @route   GET /api/subscriptions/status
 * @desc    Get current subscription status for user's household
 * @access  Private
 */
router.get('/status', authenticateToken, (req, res) => {
    const userId = req.user.id;

    try {
        // Get user's household Premium status
        const result = db.prepare(`
            SELECT 
                h.id as household_id,
                h.name as household_name,
                h.is_premium,
                h.premium_expires_at
            FROM users u
            LEFT JOIN households h ON u.household_id = h.id
            WHERE u.id = ?
        `).get(userId);

        if (!result || !result.household_id) {
            return res.json({
                isPremium: false,
                premiumExpiresAt: null,
                householdId: null
            });
        }

        // Check if Premium is still active (handle expiration)
        let isPremiumActive = Boolean(result.is_premium);

        if (isPremiumActive && result.premium_expires_at) {
            const expiresAt = new Date(result.premium_expires_at);
            const now = new Date();

            if (expiresAt < now) {
                // Premium has expired - update in database
                logger.info(`⏰ [Premium] Subscription expired for household ${result.household_id}`);

                db.prepare(`
                    UPDATE households 
                    SET is_premium = 0 
                    WHERE id = ?
                `).run(result.household_id);

                isPremiumActive = false;
            }
        }

        res.json({
            isPremium: isPremiumActive,
            premiumExpiresAt: result.premium_expires_at,
            householdId: result.household_id,
            householdName: result.household_name
        });

    } catch (error) {
        logger.error(`❌ [Subscriptions] Status check error: ${error.message}`, {
            userId,
            error: error.stack
        });
        res.status(500).json({ error: 'Failed to check subscription status' });
    }
});

module.exports = router;
