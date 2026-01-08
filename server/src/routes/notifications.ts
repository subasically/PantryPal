import express, { Response } from 'express';
const router = express.Router();
import { v4 as uuidv4 } from 'uuid';
import authenticateToken, { AuthenticatedRequest } from '../middleware/auth';

// Lazy load database
let dbInstance: any = null;
function getDb() {
	if (!dbInstance) {
		dbInstance = require('../models/database').default;
	}
	return dbInstance;
}

interface DeviceTokenRow {
	id: string;
	user_id: string;
	household_id: string | null;
	token: string;
	platform: string;
}

interface NotificationPreferencesRow {
	id: string;
	user_id: string;
	expiration_enabled: number;
	expiration_days_before: number;
	low_stock_enabled: number;
	low_stock_threshold: number;
	checkout_enabled: number;
}

/**
 * @route   POST /api/notifications/register
 * @desc    Register device token for push notifications
 * @access  Private
 */
router.post('/register', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	try {
		const { token, platform = 'ios' } = req.body;
		const userId = req.user!.id;
		const householdId = req.user!.householdId;

		if (!token) {
			return res.status(400).json({ error: 'Token is required' });
		}

		const db = getDb();

		// Upsert device token
		const existing = db.prepare(`
            SELECT id FROM device_tokens WHERE user_id = ? AND token = ?
        `).get(userId, token) as DeviceTokenRow | undefined;

		if (existing) {
			db.prepare(`
                UPDATE device_tokens SET updated_at = CURRENT_TIMESTAMP WHERE id = ?
            `).run(existing.id);
		} else {
			const id = uuidv4();
			db.prepare(`
                INSERT INTO device_tokens (id, user_id, household_id, token, platform)
                VALUES (?, ?, ?, ?, ?)
            `).run(id, userId, householdId, token, platform);
		}

		// Ensure notification preferences exist
		const prefs = db.prepare('SELECT id FROM notification_preferences WHERE user_id = ?').get(userId);
		if (!prefs) {
			db.prepare(`
                INSERT INTO notification_preferences (id, user_id)
                VALUES (?, ?)
            `).run(uuidv4(), userId);
		}

		res.json({ success: true, message: 'Device registered for push notifications' });
	} catch (error) {
		console.error('Error registering device:', error);
		res.status(500).json({ error: 'Failed to register device' });
	}
});

/**
 * @route   DELETE /api/notifications/unregister
 * @desc    Unregister device token
 * @access  Private
 */
router.delete('/unregister', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	try {
		const { token } = req.body;
		const userId = req.user!.id;

		if (!token) {
			return res.status(400).json({ error: 'Device token is required' });
		}

		const db = getDb();
		db.prepare('DELETE FROM device_tokens WHERE user_id = ? AND token = ?').run(userId, token);
		res.json({ success: true, message: 'Device unregistered' });
	} catch (error) {
		console.error('Error unregistering device:', error);
		res.status(500).json({ error: 'Failed to unregister device' });
	}
});

/**
 * @route   GET /api/notifications/preferences
 * @desc    Get notification preferences
 * @access  Private
 */
router.get('/preferences', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	try {
		const userId = req.user!.id;
		const db = getDb();

		let prefs = db.prepare(`
            SELECT expiration_enabled, expiration_days_before, 
                   low_stock_enabled, low_stock_threshold,
                   checkout_enabled
            FROM notification_preferences WHERE user_id = ?
        `).get(userId) as NotificationPreferencesRow | undefined;

		// Return defaults if no preferences exist
		if (!prefs) {
			prefs = {
				id: '',
				user_id: userId,
				expiration_enabled: 1,
				expiration_days_before: 3,
				low_stock_enabled: 1,
				low_stock_threshold: 2,
				checkout_enabled: 1
			};
		}

		// Convert to boolean for iOS
		res.json({
			expirationEnabled: Boolean(prefs.expiration_enabled),
			expirationDaysBefore: prefs.expiration_days_before,
			lowStockEnabled: Boolean(prefs.low_stock_enabled),
			lowStockThreshold: prefs.low_stock_threshold,
			checkoutEnabled: Boolean(prefs.checkout_enabled)
		});
	} catch (error) {
		console.error('Error getting preferences:', error);
		res.status(500).json({ error: 'Failed to get notification preferences' });
	}
});

/**
 * @route   PUT /api/notifications/preferences
 * @desc    Update notification preferences
 * @access  Private
 */
router.put('/preferences', authenticateToken, (req: AuthenticatedRequest, res: Response) => {
	try {
		const userId = req.user!.id;
		const {
			expirationEnabled,
			expirationDaysBefore,
			lowStockEnabled,
			lowStockThreshold,
			checkoutEnabled
		} = req.body;

		const db = getDb();

		// Upsert preferences
		const existing = db.prepare('SELECT id FROM notification_preferences WHERE user_id = ?').get(userId);

		if (existing) {
			db.prepare(`
                UPDATE notification_preferences SET
                    expiration_enabled = COALESCE(?, expiration_enabled),
                    expiration_days_before = COALESCE(?, expiration_days_before),
                    low_stock_enabled = COALESCE(?, low_stock_enabled),
                    low_stock_threshold = COALESCE(?, low_stock_threshold),
                    checkout_enabled = COALESCE(?, checkout_enabled),
                    updated_at = CURRENT_TIMESTAMP
                WHERE user_id = ?
            `).run(
				expirationEnabled !== undefined ? (expirationEnabled ? 1 : 0) : null,
				expirationDaysBefore,
				lowStockEnabled !== undefined ? (lowStockEnabled ? 1 : 0) : null,
				lowStockThreshold,
				checkoutEnabled !== undefined ? (checkoutEnabled ? 1 : 0) : null,
				userId
			);
		} else {
			db.prepare(`
                INSERT INTO notification_preferences (
                    id, user_id, expiration_enabled, expiration_days_before,
                    low_stock_enabled, low_stock_threshold, checkout_enabled
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
            `).run(
				uuidv4(),
				userId,
				expirationEnabled !== undefined ? (expirationEnabled ? 1 : 0) : 1,
				expirationDaysBefore || 3,
				lowStockEnabled !== undefined ? (lowStockEnabled ? 1 : 0) : 1,
				lowStockThreshold || 2,
				checkoutEnabled !== undefined ? (checkoutEnabled ? 1 : 0) : 1
			);
		}

		res.json({ success: true, message: 'Preferences updated' });
	} catch (error) {
		console.error('Error updating preferences:', error);
		res.status(500).json({ error: 'Failed to update notification preferences' });
	}
});

/**
 * @route   POST /api/notifications/test
 * @desc    Test push notification (for debugging)
 * @access  Private
 */
router.post('/test', authenticateToken, async (req: AuthenticatedRequest, res: Response) => {
	try {
		const { default: pushService } = await import('../services/pushNotifications');
		const result = await pushService.sendToUser(req.user!.id, {
			aps: {
				alert: {
					title: '🧪 Test Notification',
					body: 'Push notifications are working!'
				},
				sound: 'default'
			},
			type: 'test'
		});

		res.json({ success: true, results: result });
	} catch (error) {
		console.error('Error sending test notification:', error);
		res.status(500).json({ error: 'Failed to send test notification' });
	}
});

export default router;
