require('dotenv').config();

const cron = require('node-cron');
const { createApp } = require('./app');
const pushService = require('./services/pushNotifications');

const app = createApp();
const PORT = process.env.PORT || 3000;

// Start server
app.listen(PORT, () => {
    console.log(`PantryPal server running on port ${PORT}`);
    console.log(`Health check: http://localhost:${PORT}/health`);
});

// Daily check for expiring items at 9 AM
cron.schedule('0 9 * * *', async () => {
    console.log('Running daily expiration check...');
    try {
        await pushService.checkExpiringItems();
    } catch (error) {
        console.error('Error in expiration check:', error);
    }
});

// Weekly low stock check on Sundays at 10 AM
cron.schedule('0 10 * * 0', async () => {
    console.log('Running weekly low stock check...');
    try {
        await pushService.checkLowStockItems();
    } catch (error) {
        console.error('Error in low stock check:', error);
    }
});
