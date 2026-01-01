// Express app factory for testing
const express = require('express');
const cors = require('cors');
const logger = require('./utils/logger');
const requestLogger = require('./middleware/logging');

function createApp() {
    const authRoutes = require('./routes/auth');
    const productRoutes = require('./routes/products');
    const inventoryRoutes = require('./routes/inventory');
    const locationsRoutes = require('./routes/locations');
    const checkoutRoutes = require('./routes/checkout');
    const notificationsRoutes = require('./routes/notifications');
    const syncRoutes = require('./routes/sync');
    const groceryRoutes = require('./routes/grocery');

    const app = express();

    // Middleware
    app.use(cors());
    app.use(express.json());
    app.use(requestLogger); // Log all HTTP requests

    // Routes
    app.use('/api/auth', authRoutes);
    app.use('/api/products', productRoutes);
    app.use('/api/inventory', inventoryRoutes);
    app.use('/api/locations', locationsRoutes);
    app.use('/api/checkout', checkoutRoutes);
    app.use('/api/notifications', notificationsRoutes);
    app.use('/api/sync', syncRoutes);
    app.use('/api/grocery', groceryRoutes);
    
    // Test endpoints (only in non-production)
    if (process.env.NODE_ENV !== 'production' || process.env.ALLOW_TEST_ENDPOINTS === 'true') {
        const testRoutes = require('./routes/test');
        app.use('/api/test', testRoutes);
        logger.warn('⚠️  [DEV] Test endpoints enabled at /api/test');
    }
    
    // Admin routes (DEV/TEST ONLY - protected by env var)
    if (process.env.ENABLE_ADMIN_ROUTES === 'true') {
        const adminRoutes = require('./routes/admin');
        app.use('/api/admin', adminRoutes);
        logger.warn('⚠️  [DEV] Admin routes enabled - do NOT use in production!');
    }

    // Health check
    app.get('/health', (req, res) => {
        res.json({ status: 'ok', timestamp: new Date().toISOString() });
    });

    // API info
    app.get('/api', (req, res) => {
        res.json({
            name: 'PantryPal API',
            version: '1.0.0',
            endpoints: {
                auth: '/api/auth',
                products: '/api/products',
                inventory: '/api/inventory',
                locations: '/api/locations',
                checkout: '/api/checkout',
                notifications: '/api/notifications',
                sync: '/api/sync',
                grocery: '/api/grocery'
            }
        });
    });

    // Error handling
    app.use((err, req, res, next) => {
        logger.logError('Unhandled error', err, {
            path: req.path,
            method: req.method,
            userId: req.user?.id,
            householdId: req.user?.householdId
        });
        res.status(500).json({ error: 'Internal server error' });
    });

    // 404 handler
    app.use((req, res) => {
        res.status(404).json({ error: 'Not found' });
    });

    return app;
}

module.exports = { createApp };
