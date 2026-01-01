require('dotenv').config();

const cron = require('node-cron');
const { createApp } = require('./app');
const logger = require('./utils/logger');
const pushService = require('./services/pushNotifications');

const app = createApp();
const PORT = process.env.PORT || 3000;

// Start server
app.listen(PORT, () => {
    logger.info(`PantryPal server running on port ${PORT}`);
    logger.info(`Health check: http://localhost:${PORT}/health`);
    logger.info(`Environment: ${process.env.NODE_ENV || 'development'}`);
});

// Daily check for expiring items at 9 AM
cron.schedule('0 9 * * *', async () => {
    logger.info('Running daily expiration check...');
    try {
        await pushService.checkExpiringItems();
        logger.info('Daily expiration check completed');
    } catch (error) {
        logger.logError('Error in expiration check', error);
    }
});

// Weekly low stock check on Sundays at 10 AM
cron.schedule('0 10 * * 0', async () => {
    logger.info('Running weekly low stock check...');
    try {
        await pushService.checkLowStockItems();
        logger.info('Weekly low stock check completed');
    } catch (error) {
        logger.logError('Error in low stock check', error);
    }
});
