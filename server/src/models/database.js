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
            console.log('Migration successful: apple_id added');
        }
    } catch (error) {
        console.error('Migration error (apple_id):', error);
    }
    
    // Migration: Add premium_expires_at to households if it doesn't exist
    try {
        const tableInfo = db.prepare("PRAGMA table_info(households)").all();
        const hasPremiumExpires = tableInfo.some(col => col.name === 'premium_expires_at');
        
        if (!hasPremiumExpires) {
            console.log('Migrating: Adding premium_expires_at column to households table...');
            db.prepare('ALTER TABLE households ADD COLUMN premium_expires_at DATETIME').run();
            console.log('Migration successful: premium_expires_at added');
        }
    } catch (error) {
        console.error('Migration error (premium_expires_at):', error);
    }
    
    // Migration: Add brand and upc to grocery_items if they don't exist
    try {
        const tableInfo = db.prepare("PRAGMA table_info(grocery_items)").all();
        const hasBrand = tableInfo.some(col => col.name === 'brand');
        const hasUpc = tableInfo.some(col => col.name === 'upc');
        
        if (!hasBrand) {
            console.log('Migrating: Adding brand column to grocery_items table...');
            db.prepare('ALTER TABLE grocery_items ADD COLUMN brand TEXT').run();
            console.log('Migration successful: brand added');
        }
        
        if (!hasUpc) {
            console.log('Migrating: Adding upc column to grocery_items table...');
            db.prepare('ALTER TABLE grocery_items ADD COLUMN upc TEXT').run();
            db.prepare('CREATE INDEX IF NOT EXISTS idx_grocery_items_upc ON grocery_items(upc)').run();
            console.log('Migration successful: upc added');
        }
    } catch (error) {
        console.error('Migration error (grocery_items brand/upc):', error);
    }

    console.log('Database initialized successfully');
}

// Initialize on first load
initializeDatabase();

module.exports = db;
