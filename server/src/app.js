// Express app factory for testing
const express = require('express');
const cors = require('cors');

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

    // Routes
    app.use('/api/auth', authRoutes);
    app.use('/api/products', productRoutes);
    app.use('/api/inventory', inventoryRoutes);
    app.use('/api/locations', locationsRoutes);
    app.use('/api/checkout', checkoutRoutes);
    app.use('/api/notifications', notificationsRoutes);
    app.use('/api/sync', syncRoutes);
    app.use('/api/grocery', groceryRoutes);

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
        console.error('Unhandled error:', err);
        res.status(500).json({ error: 'Internal server error' });
    });

    // 404 handler
    app.use((req, res) => {
        res.status(404).json({ error: 'Not found' });
    });

    return app;
}

module.exports = { createApp };
