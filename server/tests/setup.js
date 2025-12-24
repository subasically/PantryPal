// Test setup - override database path for tests
const path = require('path');
const fs = require('fs');

const TEST_DB_PATH = path.join(__dirname, 'test.db');

// Set environment variable before requiring any modules
process.env.DATABASE_PATH = TEST_DB_PATH;
process.env.JWT_SECRET = 'test-secret-key';
process.env.NODE_ENV = 'test';

// Clean up test database
function cleanupTestDb() {
    if (fs.existsSync(TEST_DB_PATH)) {
        fs.unlinkSync(TEST_DB_PATH);
    }
}

module.exports = { TEST_DB_PATH, cleanupTestDb };
