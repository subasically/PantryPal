const http2 = require('http2');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const path = require('path');
const db = require('../models/database');

class PushNotificationService {
    constructor() {
        this.keyId = process.env.APNS_KEY_ID;
        this.teamId = process.env.APNS_TEAM_ID;
        this.bundleId = process.env.APNS_BUNDLE_ID || 'me.subasically.pantrypal';
        this.keyPath = process.env.APNS_KEY_PATH;
        this.isProduction = process.env.NODE_ENV === 'production';
        
        this.apnsHost = this.isProduction 
            ? 'api.push.apple.com' 
            : 'api.sandbox.push.apple.com';
    }

    // Generate APNs JWT token
    generateToken() {
        if (!this.keyPath || !fs.existsSync(this.keyPath)) {
            console.warn('APNs key not configured');
            return null;
        }

        const key = fs.readFileSync(this.keyPath);
        const token = jwt.sign({}, key, {
            algorithm: 'ES256',
            header: {
                alg: 'ES256',
                kid: this.keyId
            },
            issuer: this.teamId,
            expiresIn: '1h'
        });

        return token;
    }

    // Send push notification to a device
    async sendNotification(deviceToken, payload) {
        const token = this.generateToken();
        if (!token) {
            console.log('Push notification skipped - APNs not configured');
            return { success: false, reason: 'APNs not configured' };
        }

        return new Promise((resolve, reject) => {
            const client = http2.connect(`https://${this.apnsHost}:443`);

            client.on('error', (err) => {
                console.error('APNs connection error:', err);
                resolve({ success: false, reason: err.message });
            });

            const headers = {
                ':method': 'POST',
                ':path': `/3/device/${deviceToken}`,
                'authorization': `bearer ${token}`,
                'apns-topic': this.bundleId,
                'apns-push-type': 'alert',
                'apns-priority': '10',
                'apns-expiration': '0'
            };

            const body = JSON.stringify(payload);
            const req = client.request(headers);

            let data = '';
            req.on('response', (headers) => {
                const status = headers[':status'];
                req.on('data', (chunk) => { data += chunk; });
                req.on('end', () => {
                    client.close();
                    if (status === 200) {
                        resolve({ success: true });
                    } else {
                        resolve({ success: false, status, reason: data });
                    }
                });
            });

            req.write(body);
            req.end();
        });
    }

    // Send notification to all devices in a household
    async sendToHousehold(householdId, payload) {
        const tokens = db.prepare(`
            SELECT DISTINCT dt.token, dt.user_id 
            FROM device_tokens dt
            JOIN notification_preferences np ON dt.user_id = np.user_id
            WHERE dt.household_id = ?
        `).all(householdId);

        const results = [];
        for (const { token } of tokens) {
            const result = await this.sendNotification(token, payload);
            results.push({ token, ...result });
            
            // Remove invalid tokens
            if (!result.success && result.status === 410) {
                db.prepare('DELETE FROM device_tokens WHERE token = ?').run(token);
            }
        }
        return results;
    }

    // Send notification to a specific user
    async sendToUser(userId, payload) {
        const tokens = db.prepare(`
            SELECT token FROM device_tokens WHERE user_id = ?
        `).all(userId);

        const results = [];
        for (const { token } of tokens) {
            const result = await this.sendNotification(token, payload);
            results.push({ token, ...result });
            
            if (!result.success && result.status === 410) {
                db.prepare('DELETE FROM device_tokens WHERE token = ?').run(token);
            }
        }
        return results;
    }

    // Check for expiring items and send notifications
    async checkExpiringItems() {
        console.log('Checking for expiring items...');

        // Get all households with notification preferences
        const households = db.prepare(`
            SELECT DISTINCT h.id, h.name 
            FROM households h
            JOIN users u ON u.household_id = h.id
            JOIN notification_preferences np ON np.user_id = u.id
            WHERE np.expiration_enabled = 1
        `).all();

        for (const household of households) {
            // Get users with expiration notifications enabled
            const users = db.prepare(`
                SELECT u.id, u.name, np.expiration_days_before
                FROM users u
                JOIN notification_preferences np ON np.user_id = u.id
                WHERE u.household_id = ? AND np.expiration_enabled = 1
            `).all(household.id);

            for (const user of users) {
                const daysBefore = user.expiration_days_before || 3;
                
                // Get items expiring within the notification window
                const expiringItems = db.prepare(`
                    SELECT i.id, p.name, p.brand, i.expiration_date,
                           julianday(i.expiration_date) - julianday('now') as days_until
                    FROM inventory i
                    JOIN products p ON i.product_id = p.id
                    WHERE i.household_id = ?
                      AND i.expiration_date IS NOT NULL
                      AND julianday(i.expiration_date) - julianday('now') BETWEEN 0 AND ?
                    ORDER BY i.expiration_date ASC
                `).all(household.id, daysBefore);

                if (expiringItems.length > 0) {
                    const todayExpiring = expiringItems.filter(i => Math.floor(i.days_until) === 0);
                    const soonExpiring = expiringItems.filter(i => Math.floor(i.days_until) > 0);

                    // Send notification for items expiring today
                    if (todayExpiring.length > 0) {
                        const itemNames = todayExpiring.slice(0, 3).map(i => 
                            i.brand ? `${i.brand} ${i.name}` : i.name
                        ).join(', ');
                        
                        const payload = {
                            aps: {
                                alert: {
                                    title: '⚠️ Items Expiring Today!',
                                    body: todayExpiring.length === 1 
                                        ? `${itemNames} expires today`
                                        : `${todayExpiring.length} items expire today: ${itemNames}${todayExpiring.length > 3 ? '...' : ''}`
                                },
                                sound: 'default',
                                badge: todayExpiring.length
                            },
                            type: 'expiration',
                            householdId: household.id
                        };
                        await this.sendToUser(user.id, payload);
                    }

                    // Send notification for items expiring soon (once daily)
                    if (soonExpiring.length > 0) {
                        const itemNames = soonExpiring.slice(0, 3).map(i => 
                            i.brand ? `${i.brand} ${i.name}` : i.name
                        ).join(', ');

                        const payload = {
                            aps: {
                                alert: {
                                    title: '📅 Items Expiring Soon',
                                    body: soonExpiring.length === 1 
                                        ? `${itemNames} expires in ${Math.ceil(soonExpiring[0].days_until)} days`
                                        : `${soonExpiring.length} items expiring soon: ${itemNames}${soonExpiring.length > 3 ? '...' : ''}`
                                },
                                sound: 'default'
                            },
                            type: 'expiration_warning',
                            householdId: household.id
                        };
                        await this.sendToUser(user.id, payload);
                    }
                }
            }
        }
        console.log('Expiring items check completed');
    }

    // Check for low stock items
    async checkLowStockItems() {
        console.log('Checking for low stock items...');

        const users = db.prepare(`
            SELECT u.id, u.household_id, np.low_stock_threshold
            FROM users u
            JOIN notification_preferences np ON np.user_id = u.id
            WHERE np.low_stock_enabled = 1
        `).all();

        for (const user of users) {
            const threshold = user.low_stock_threshold || 2;
            
            const lowStockItems = db.prepare(`
                SELECT p.name, p.brand, SUM(i.quantity) as total_quantity
                FROM inventory i
                JOIN products p ON i.product_id = p.id
                WHERE i.household_id = ?
                GROUP BY i.product_id
                HAVING total_quantity <= ? AND total_quantity > 0
            `).all(user.household_id, threshold);

            if (lowStockItems.length > 0) {
                const itemNames = lowStockItems.slice(0, 3).map(i => 
                    i.brand ? `${i.brand} ${i.name}` : i.name
                ).join(', ');

                const payload = {
                    aps: {
                        alert: {
                            title: '📦 Low Stock Alert',
                            body: lowStockItems.length === 1
                                ? `${itemNames} is running low`
                                : `${lowStockItems.length} items running low: ${itemNames}${lowStockItems.length > 3 ? '...' : ''}`
                        },
                        sound: 'default'
                    },
                    type: 'low_stock',
                    householdId: user.household_id
                };
                await this.sendToUser(user.id, payload);
            }
        }
        console.log('Low stock check completed');
    }

    // Send checkout notification to household members
    async sendCheckoutNotification(householdId, userId, itemName, remainingQuantity) {
        // Get other users in household who have checkout notifications enabled
        const users = db.prepare(`
            SELECT u.id, u.name
            FROM users u
            JOIN notification_preferences np ON np.user_id = u.id
            WHERE u.household_id = ? AND u.id != ? AND np.checkout_enabled = 1
        `).all(householdId, userId);

        const checkoutUser = db.prepare('SELECT name FROM users WHERE id = ?').get(userId);
        const userName = checkoutUser?.name || 'Someone';

        for (const user of users) {
            let body;
            if (remainingQuantity === 0) {
                body = `${userName} took the last ${itemName}`;
            } else if (remainingQuantity <= 2) {
                body = `${userName} took ${itemName}. Only ${remainingQuantity} left!`;
            } else {
                body = `${userName} took ${itemName}. ${remainingQuantity} remaining.`;
            }

            const payload = {
                aps: {
                    alert: {
                        title: '🛒 Item Checked Out',
                        body
                    },
                    sound: remainingQuantity <= 2 ? 'default' : null
                },
                type: 'checkout',
                householdId
            };
            await this.sendToUser(user.id, payload);
        }
    }
}

module.exports = new PushNotificationService();
