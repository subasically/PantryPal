-- PantryPal Database Schema

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    password_hash TEXT,
    first_name TEXT,
    last_name TEXT,
    household_id TEXT,
    apple_id TEXT UNIQUE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Households table (for shared access)
CREATE TABLE IF NOT EXISTS households (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id TEXT NOT NULL,
    invite_code TEXT UNIQUE,
    is_premium INTEGER DEFAULT 0,
    premium_expires_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (owner_id) REFERENCES users(id)
);

-- Products table (UPC lookup cache + custom items)
CREATE TABLE IF NOT EXISTS products (
    id TEXT PRIMARY KEY,
    upc TEXT UNIQUE,
    name TEXT NOT NULL,
    brand TEXT,
    description TEXT,
    image_url TEXT,
    category TEXT,
    is_custom INTEGER DEFAULT 0,
    household_id TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (household_id) REFERENCES households(id)
);

-- Locations table (hierarchical: Basement Pantry -> First Rack -> 2nd Shelf)
CREATE TABLE IF NOT EXISTS locations (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    name TEXT NOT NULL,
    type TEXT DEFAULT 'pantry',
    parent_id TEXT,
    level INTEGER DEFAULT 0,
    sort_order INTEGER DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (household_id) REFERENCES households(id),
    FOREIGN KEY (parent_id) REFERENCES locations(id)
);

-- Inventory table
CREATE TABLE IF NOT EXISTS inventory (
    id TEXT PRIMARY KEY,
    product_id TEXT NOT NULL,
    household_id TEXT NOT NULL,
    location_id TEXT,
    quantity INTEGER DEFAULT 1,
    unit TEXT DEFAULT 'pcs',
    expiration_date DATE,
    notes TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id),
    FOREIGN KEY (household_id) REFERENCES households(id),
    FOREIGN KEY (location_id) REFERENCES locations(id)
);

-- Checkout history table (consumption tracking)
CREATE TABLE IF NOT EXISTS checkout_history (
    id TEXT PRIMARY KEY,
    inventory_id TEXT,
    product_id TEXT NOT NULL,
    household_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    quantity INTEGER DEFAULT 1,
    checked_out_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (product_id) REFERENCES products(id),
    FOREIGN KEY (household_id) REFERENCES households(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- Sync log for offline-first sync
CREATE TABLE IF NOT EXISTS sync_log (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,
    payload TEXT,
    client_timestamp DATETIME NOT NULL,
    server_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    synced INTEGER DEFAULT 0,
    FOREIGN KEY (household_id) REFERENCES households(id)
);

-- Household invite codes
CREATE TABLE IF NOT EXISTS invite_codes (
    id TEXT PRIMARY KEY,
    household_id TEXT NOT NULL,
    code TEXT UNIQUE NOT NULL,
    created_by TEXT NOT NULL,
    expires_at DATETIME NOT NULL,
    used_by TEXT,
    used_at DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (household_id) REFERENCES households(id),
    FOREIGN KEY (created_by) REFERENCES users(id),
    FOREIGN KEY (used_by) REFERENCES users(id)
);

-- Grocery list items
CREATE TABLE IF NOT EXISTS grocery_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    household_id TEXT NOT NULL,
    name TEXT NOT NULL,
    brand TEXT,
    upc TEXT,
    normalized_name TEXT NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (household_id) REFERENCES households(id),
    UNIQUE(household_id, normalized_name)
);

CREATE INDEX IF NOT EXISTS idx_invite_codes_code ON invite_codes(code);
CREATE INDEX IF NOT EXISTS idx_invite_codes_household ON invite_codes(household_id);
CREATE INDEX IF NOT EXISTS idx_grocery_items_household ON grocery_items(household_id);
CREATE INDEX IF NOT EXISTS idx_grocery_items_normalized ON grocery_items(normalized_name);
CREATE INDEX IF NOT EXISTS idx_grocery_items_upc ON grocery_items(upc);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_products_upc ON products(upc);
CREATE INDEX IF NOT EXISTS idx_products_household ON products(household_id);
CREATE INDEX IF NOT EXISTS idx_inventory_household ON inventory(household_id);
CREATE INDEX IF NOT EXISTS idx_inventory_product ON inventory(product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_expiration ON inventory(expiration_date);
CREATE INDEX IF NOT EXISTS idx_inventory_location ON inventory(location_id);
CREATE INDEX IF NOT EXISTS idx_sync_log_household ON sync_log(household_id);
CREATE INDEX IF NOT EXISTS idx_sync_log_timestamp ON sync_log(server_timestamp);
CREATE INDEX IF NOT EXISTS idx_users_household ON users(household_id);
CREATE INDEX IF NOT EXISTS idx_locations_household ON locations(household_id);
CREATE INDEX IF NOT EXISTS idx_locations_parent ON locations(parent_id);
CREATE INDEX IF NOT EXISTS idx_checkout_history_household ON checkout_history(household_id);
CREATE INDEX IF NOT EXISTS idx_checkout_history_product ON checkout_history(product_id);
CREATE INDEX IF NOT EXISTS idx_checkout_history_date ON checkout_history(checked_out_at);

-- Device tokens for push notifications
CREATE TABLE IF NOT EXISTS device_tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    household_id TEXT NOT NULL,
    token TEXT NOT NULL,
    platform TEXT DEFAULT 'ios',
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (household_id) REFERENCES households(id) ON DELETE CASCADE,
    UNIQUE(user_id, token)
);

-- Notification preferences
CREATE TABLE IF NOT EXISTS notification_preferences (
    id TEXT PRIMARY KEY,
    user_id TEXT UNIQUE NOT NULL,
    expiration_enabled INTEGER DEFAULT 1,
    expiration_days_before INTEGER DEFAULT 3,
    low_stock_enabled INTEGER DEFAULT 1,
    low_stock_threshold INTEGER DEFAULT 2,
    checkout_enabled INTEGER DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_device_tokens_user ON device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_household ON device_tokens(household_id);
CREATE INDEX IF NOT EXISTS idx_notification_preferences_user ON notification_preferences(user_id);
