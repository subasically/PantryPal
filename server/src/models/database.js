const Database = require('better-sqlite3');
const path = require('path');
const fs = require('fs');

const dbPath = process.env.DATABASE_PATH || path.join(__dirname, '../../db/pantrypal.db');
const schemaPath = path.join(__dirname, '../../db/schema.sql');

const db = new Database(dbPath);

// Enable foreign keys
db.pragma('foreign_keys = ON');

// Initialize database with schema
function initializeDatabase() {
    const schema = fs.readFileSync(schemaPath, 'utf8');
    db.exec(schema);
    
    // Migration: Add apple_id to users if it doesn't exist
    try {
        const tableInfo = db.prepare("PRAGMA table_info(users)").all();
        const hasAppleId = tableInfo.some(col => col.name === 'apple_id');
        
        if (!hasAppleId) {
            console.log('Migrating: Adding apple_id column to users table...');
            db.prepare('ALTER TABLE users ADD COLUMN apple_id TEXT').run();
            db.prepare('CREATE UNIQUE INDEX IF NOT EXISTS idx_users_apple_id ON users(apple_id)').run();
            console.log('Migration successful');
        }
    } catch (error) {
        console.error('Migration error:', error);
    }

    console.log('Database initialized successfully');
}

// Initialize on first load
initializeDatabase();

module.exports = db;
