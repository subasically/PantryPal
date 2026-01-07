const { v4: uuidv4 } = require('uuid');
const db = require('../models/database');
const { isHouseholdPremium } = require('../utils/premiumHelper');

/**
 * Create default storage locations for a household (DEPRECATED - now client-managed)
 * Kept as fallback for backward compatibility
 * @param {string} householdId - Household ID
 */
function createDefaultLocations(householdId) {
    // This function is deprecated. Locations are now created by the iOS app
    // after household creation to allow easier updates to default locations.
    // Keeping this as a no-op for backward compatibility.
    console.log('⚠️ [Deprecated] createDefaultLocations called - locations are now client-managed');
}

/**
 * Create a new household
 * @param {string} userId - User ID
 * @param {string} name - Household name (optional, defaults to "<Last Name> Household" or "My Household")
 * @returns {Object} { id, name, isPremium }
 */
function createHousehold(userId, name) {
    // Check if user already has a household
    const user = db.prepare('SELECT household_id, last_name, email FROM users WHERE id = ?').get(userId);
    if (user.household_id) {
        throw new Error('User already belongs to a household');
    }

    // Generate default name if not provided
    if (!name) {
        if (user.last_name && user.last_name.trim()) {
            name = `${user.last_name} Household`;
        } else if (user.email) {
            // Extract name from email as fallback (e.g., "john.doe@example.com" -> "Doe")
            const emailName = user.email.split('@')[0];
            const parts = emailName.split(/[._-]/);
            // Use last part as surname, capitalize it
            const lastName = parts[parts.length - 1];
            if (lastName && lastName.length > 0) {
                name = `${lastName.charAt(0).toUpperCase() + lastName.slice(1)} Household`;
            } else {
                name = 'My Household';
            }
        } else {
            name = 'My Household';
        }
    }

    const householdId = uuidv4();

    const transaction = db.transaction(() => {
        // Create household with owner
        db.prepare('INSERT INTO households (id, name, owner_id) VALUES (?, ?, ?)').run(householdId, name, userId);

        // Update user
        db.prepare('UPDATE users SET household_id = ? WHERE id = ?').run(householdId, userId);

        // Note: Default locations are now created by the iOS app after household creation
        // This allows for easier updates to default locations without server deployments
    });

    transaction();

    return {
        id: householdId,
        name,
        isPremium: false
    };
}

/**
 * Generate household invite code
 * @param {string} householdId - Household ID
 * @param {string} userId - User ID creating the invite
 * @returns {Object} { code, expiresAt, householdName }
 */
function generateInviteCode(householdId, userId) {
    // Check if household is premium
    const household = db.prepare('SELECT is_premium, name FROM households WHERE id = ?').get(householdId);
    if (!household.is_premium) {
        const error = new Error('Household sharing is a Premium feature');
        error.code = 'PREMIUM_REQUIRED';
        throw error;
    }

    // Generate a 6-character alphanumeric code
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Exclude confusing chars (0,O,1,I)
    let code = '';
    for (let i = 0; i < 6; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }

    const id = uuidv4();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(); // 24 hours

    db.prepare(`
        INSERT INTO invite_codes (id, household_id, code, created_by, expires_at)
        VALUES (?, ?, ?, ?, ?)
    `).run(id, householdId, code, userId, expiresAt);

    return {
        code,
        expiresAt,
        householdName: household.name || 'Unknown Household'
    };
}

/**
 * Validate invite code
 * @param {string} code - Invite code
 * @returns {Object} { valid, householdId, householdName, memberCount, expiresAt }
 */
function validateInviteCode(code) {
    const invite = db.prepare(`
        SELECT ic.*, h.name as household_name
        FROM invite_codes ic
        JOIN households h ON ic.household_id = h.id
        WHERE ic.code = ? AND ic.used_by IS NULL AND ic.expires_at > datetime('now')
    `).get(code.toUpperCase());

    if (!invite) {
        throw new Error('Invalid or expired invite code');
    }

    // Count household members
    const memberCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE household_id = ?').get(invite.household_id);

    return {
        valid: true,
        householdId: invite.household_id,
        householdName: invite.household_name,
        memberCount: memberCount.count,
        expiresAt: invite.expires_at
    };
}

/**
 * Join household with invite code
 * @param {string} userId - User ID
 * @param {string} code - Invite code
 * @returns {Object} { success, household }
 */
function joinHousehold(userId, code) {
    const invite = db.prepare(`
        SELECT * FROM invite_codes
        WHERE code = ? AND used_by IS NULL AND expires_at > datetime('now')
    `).get(code.toUpperCase());

    if (!invite) {
        throw new Error('Invalid or expired invite code');
    }

    // Update user's household
    db.prepare('UPDATE users SET household_id = ?, updated_at = ? WHERE id = ?')
        .run(invite.household_id, new Date().toISOString(), userId);

    // Mark invite as used
    db.prepare('UPDATE invite_codes SET used_by = ?, used_at = ? WHERE id = ?')
        .run(userId, new Date().toISOString(), invite.id);

    const household = db.prepare('SELECT * FROM households WHERE id = ?').get(invite.household_id);

    return {
        success: true,
        household: {
            id: household.id,
            name: household.name
        }
    };
}

/**
 * Get household members
 * @param {string} householdId - Household ID
 * @returns {Array} Array of member objects
 */
function getHouseholdMembers(householdId) {
    // Get household owner
    const household = db.prepare('SELECT owner_id FROM households WHERE id = ?').get(householdId);
    const ownerId = household?.owner_id;

    const members = db.prepare(`
        SELECT id, email, first_name, last_name, created_at
        FROM users
        WHERE household_id = ?
        ORDER BY created_at ASC
    `).all(householdId);

    return members.map(m => ({
        id: m.id,
        email: m.email,
        firstName: m.first_name || '',
        lastName: m.last_name || '',
        name: `${m.first_name || ''} ${m.last_name || ''}`.trim() || 'Member',
        isOwner: m.id === ownerId,
        createdAt: m.created_at
    }));
}

/**
 * Get active invite codes for household
 * @param {string} householdId - Household ID
 * @returns {Array} Array of invite codes
 */
function getActiveInviteCodes(householdId) {
    const invites = db.prepare(`
        SELECT code, expires_at, created_at
        FROM invite_codes
        WHERE household_id = ? AND used_by IS NULL AND expires_at > datetime('now')
        ORDER BY created_at DESC
    `).all(householdId);

    return invites;
}

/**
 * Reset household data (wipe inventory, history, custom products, locations)
 * @param {string} householdId - Household ID
 * @param {string} userId - User ID performing the reset
 */
function resetHouseholdData(householdId, userId) {
    console.log(`🗑️ [Reset] Wiping data for household ${householdId} by user ${userId}`);

    const deleteInventory = db.prepare('DELETE FROM inventory WHERE household_id = ?');
    const deleteHistory = db.prepare('DELETE FROM checkout_history WHERE household_id = ?');
    const deleteCustomProducts = db.prepare('DELETE FROM products WHERE household_id = ? AND is_custom = 1');
    const deleteLocations = db.prepare('DELETE FROM locations WHERE household_id = ?');
    const deleteGrocery = db.prepare('DELETE FROM grocery_items WHERE household_id = ?');
    const deleteSyncLog = db.prepare('DELETE FROM sync_log WHERE household_id = ?');
    const deleteInviteCodes = db.prepare('DELETE FROM invite_codes WHERE household_id = ?');

    const transaction = db.transaction(() => {
        const invResult = deleteInventory.run(householdId);
        console.log(`🗑️ [Reset] Deleted ${invResult.changes} inventory items`);

        const histResult = deleteHistory.run(householdId);
        console.log(`🗑️ [Reset] Deleted ${histResult.changes} history records`);

        const prodResult = deleteCustomProducts.run(householdId);
        console.log(`🗑️ [Reset] Deleted ${prodResult.changes} custom products`);

        const locResult = deleteLocations.run(householdId);
        console.log(`🗑️ [Reset] Deleted ${locResult.changes} locations`);

        const groceryResult = deleteGrocery.run(householdId);
        console.log(`🗑️ [Reset] Deleted ${groceryResult.changes} grocery items`);

        const syncResult = deleteSyncLog.run(householdId);
        console.log(`🗑️ [Reset] Deleted ${syncResult.changes} sync log entries`);

        const inviteResult = deleteInviteCodes.run(householdId);
        console.log(`🗑️ [Reset] Deleted ${inviteResult.changes} invite codes`);

        // Re-seed default locations so the app isn't empty
        createDefaultLocations(householdId);
        console.log(`🗑️ [Reset] Re-created default locations`);
    });

    transaction();
    console.log(`✅ [Reset] Transaction completed for household ${householdId}`);

    return { success: true, message: 'Household data reset successfully' };
}

module.exports = {
    createDefaultLocations,
    createHousehold,
    generateInviteCode,
    validateInviteCode,
    joinHousehold,
    getHouseholdMembers,
    getActiveInviteCodes,
    resetHouseholdData
};
