import express, { Response } from 'express';
const router = express.Router();
import authenticateToken, { AuthenticatedRequest } from '../middleware/auth';
import logger from '../utils/logger';
import db from '../models/database';

// Use imported database directly
function getDb() {
	return db;
}

interface UserRow {
	id: string;
	household_id: string | null;
}

interface HouseholdRow {
	id: string;
	name: string;
	is_premium: number;
	premium_expires_at: string | null;
	created_at: string;
}

interface SubscriptionStatusRow {
	household_id: string | null;
	household_name: string | null;
	is_premium: number;
	premium_expires_at: string | null;
}

/**
 * @route   POST /api/subscriptions/validate
 * @desc    Validate a StoreKit transaction receipt and update household Premium status
 * @access  Private
 */
router.post('/validate', authenticateToken, ((req: AuthenticatedRequest, res: Response) => {
	const { transactionId, productId, originalTransactionId, expiresAt } = req.body;
	const userId = req.user!.id;

	logger.info(`🍎 [StoreKit] Validating receipt for user ${userId}`, {
		transactionId,
		productId,
		expiresAt
	});

	try {
		// Validate required fields
		if (!transactionId || !productId || !originalTransactionId) {
			logger.warn(`⚠️  [StoreKit] Missing required fields`, { body: req.body });
			res.status(400).json({ error: 'Missing required transaction fields' });
			return;
		}

		const db = getDb();

		// Get user's household
		const user = db.prepare('SELECT household_id FROM users WHERE id = ?').get(userId) as UserRow | undefined;

		if (!user) {
			logger.error(`❌ [StoreKit] User not found: ${userId}`);
			res.status(404).json({ error: 'User not found' });
			return;
		}

		if (!user.household_id) {
			logger.error(`❌ [StoreKit] User ${userId} has no household`);
			res.status(400).json({ error: 'User must belong to a household to purchase Premium' });
			return;
		}

		// Calculate expiration timestamp
		// For iOS, the expiresAt is already in ISO8601 format from transaction.expirationDate
		const premiumExpiresAt: string | null = expiresAt || null;

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

		// Fetch updated household info
		const household = db.prepare(`
            SELECT id, name, is_premium, premium_expires_at, created_at 
            FROM households 
            WHERE id = ?
        `).get(user.household_id) as HouseholdRow;

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

	} catch (error: any) {
		logger.error(`❌ [StoreKit] Validation error: ${error.message}`, {
			userId,
			transactionId,
			error: error.stack
		});
		res.status(500).json({ error: 'Failed to validate subscription' });
	}
}) as unknown as express.RequestHandler);

/**
 * @route   GET /api/subscriptions/status
 * @desc    Get current subscription status for user's household
 * @access  Private
 */
router.get('/status', authenticateToken, ((req: AuthenticatedRequest, res: Response) => {
	const userId = req.user!.id;

	try {
		const db = getDb();

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
        `).get(userId) as SubscriptionStatusRow | undefined;

		if (!result || !result.household_id) {
			res.json({
				isPremium: false,
				premiumExpiresAt: null,
				householdId: null
			});
			return;
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

	} catch (error: any) {
		logger.error(`❌ [Subscriptions] Status check error: ${error.message}`, {
			userId,
			error: error.stack
		});
		res.status(500).json({ error: 'Failed to check subscription status' });
	}
}) as unknown as express.RequestHandler);

export default router;
