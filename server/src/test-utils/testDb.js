/**
 * Test Database Utilities
 * 
 * Provides isolated SQLite database for each test run with:
 * - Per-process database files (no conflicts)
 * - Schema initialization
 * - Clean teardown
 */

const Database = require('better-sqlite3');
const fs = require('fs');
const path = require('path');

let testDb = null;
let testDbPath = null;

/**
 * Creates a test database with schema
 * @returns {Database} SQLite database instance
 */
function createTestDb() {
    if (testDb) {
        return testDb;
    }

    // Create temp directory if it doesn't exist
    const tmpDir = path.join(__dirname, '../../tmp');
    if (!fs.existsSync(tmpDir)) {
        fs.mkdirSync(tmpDir, { recursive: true });
    }

    // Create unique database file for this test run
    testDbPath = path.join(tmpDir, `test-db-${process.pid}-${Date.now()}.sqlite`);
    
    console.log(`📂 [Test DB] Creating test database: ${testDbPath}`);
    
    testDb = new Database(testDbPath);
    
    // Configure SQLite
    testDb.pragma('journal_mode = WAL');
    testDb.pragma('busy_timeout = 5000');
    
    // Load schema
    const schemaPath = path.join(__dirname, '../../db/schema.sql');
    const schema = fs.readFileSync(schemaPath, 'utf8');
    
    // Execute schema (split by semicolon, filter empty statements)
    const statements = schema
        .split(';')
        .map(s => s.trim())
        .filter(s => s.length > 0);
    
    for (const statement of statements) {
        try {
            testDb.exec(statement);
        } catch (error) {
            console.error(`Failed to execute statement: ${statement.substring(0, 50)}...`);
            throw error;
        }
    }
    
    console.log('✅ [Test DB] Schema loaded successfully');
    
    return testDb;
}

/**
 * Resets database by truncating all tables
 */
function resetDb() {
    if (!testDb) {
        throw new Error('Test database not initialized. Call createTestDb() first.');
    }
    
    console.log('🗑️  [Test DB] Resetting database...');
    
    // Get all tables
    const tables = testDb
        .prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'")
        .all()
        .map(row => row.name);
    
    // Disable foreign keys temporarily
    testDb.exec('PRAGMA foreign_keys = OFF');
    
    // Truncate all tables
    for (const table of tables) {
        testDb.exec(`DELETE FROM ${table}`);
    }
    
    // Re-enable foreign keys
    testDb.exec('PRAGMA foreign_keys = ON');
    
    console.log(`✅ [Test DB] Reset complete (${tables.length} tables cleared)`);
}

/**
 * Closes database connection and deletes file
 */
function closeDb() {
    if (testDb) {
        console.log('🔒 [Test DB] Closing database...');
        testDb.close();
        testDb = null;
    }
    
    if (testDbPath && fs.existsSync(testDbPath)) {
        console.log(`🗑️  [Test DB] Deleting test database: ${testDbPath}`);
        try {
            // Delete database file and WAL/SHM files
            fs.unlinkSync(testDbPath);
            const walPath = testDbPath + '-wal';
            const shmPath = testDbPath + '-shm';
            if (fs.existsSync(walPath)) fs.unlinkSync(walPath);
            if (fs.existsSync(shmPath)) fs.unlinkSync(shmPath);
        } catch (error) {
            console.error(`Failed to delete test database: ${error.message}`);
        }
        testDbPath = null;
    }
}

/**
 * Get current test database instance
 */
function getTestDb() {
    if (!testDb) {
        throw new Error('Test database not initialized. Call createTestDb() first.');
    }
    return testDb;
}

module.exports = {
    createTestDb,
    resetDb,
    closeDb,
    getTestDb
};
