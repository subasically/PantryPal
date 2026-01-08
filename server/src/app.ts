// Express app factory for testing
import express, { Request, Response, NextFunction, ErrorRequestHandler } from 'express';
import cors from 'cors';
import logger from './utils/logger';
import requestLogger from './middleware/logging';
import { generalLimiter, upcLookupLimiter, authLimiter } from './middleware/rateLimiter';

export function createApp() {
    const authRoutes = require('./routes/auth').default;
    const householdRoutes = require('./routes/household');
    const productRoutes = require('./routes/products').default;
    const inventoryRoutes = require('./routes/inventory').default;
    const locationsRoutes = require('./routes/locations');
    const checkoutRoutes = require('./routes/checkout');
    const notificationsRoutes = require('./routes/notifications');
    const syncRoutes = require('./routes/sync').default;
    const groceryRoutes = require('./routes/grocery');
    const subscriptionsRoutes = require('./routes/subscriptions');

    const app = express();

    // Trust proxy for rate limiting (required for correct IP detection behind proxies/load balancers)
    app.set('trust proxy', 1);

    // Middleware
    app.use(cors());
    app.use(express.json());
    app.use(requestLogger); // Log all HTTP requests

    // Apply general rate limiter to all API routes (except health check)
    app.use('/api', generalLimiter);

    // Routes with specific rate limiters
    app.use('/api/auth', authLimiter, authRoutes);

    // Household routes - use general limiter only (not auth limiter)
    // These need more lenient limits for onboarding flow (join/invite validation)
    app.use('/api/household', householdRoutes);

    // Apply UPC lookup rate limiter before product routes
    app.use('/api/products/lookup', upcLookupLimiter);
    app.use('/api/products', productRoutes);

    // Other routes (general limiter already applied above)
    app.use('/api/inventory', inventoryRoutes);
    app.use('/api/locations', locationsRoutes);
    app.use('/api/checkout', checkoutRoutes);
    app.use('/api/notifications', notificationsRoutes);
    app.use('/api/sync', syncRoutes);
    app.use('/api/grocery', groceryRoutes);
    app.use('/api/subscriptions', subscriptionsRoutes);

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
    app.get('/health', (req: Request, res: Response) => {
        res.json({ status: 'ok', timestamp: new Date().toISOString() });
    });

    // API info
    app.get('/api', (req: Request, res: Response) => {
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
    const errorHandler: ErrorRequestHandler = (err, req, res, next) => {
        logger.logError('Unhandled error', err, {
            path: req.path,
            method: req.method,
            userId: (req as any).user?.id,
            householdId: (req as any).user?.householdId
        });
        res.status(500).json({ error: 'Internal server error' });
    };
    
    app.use(errorHandler);

    // 404 handler
    app.use((req: Request, res: Response) => {
        res.status(404).json({ error: 'Not found' });
    });

    return app;
}
