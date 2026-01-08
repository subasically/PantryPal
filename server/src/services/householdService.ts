import { v4 as uuidv4 } from 'uuid';

// Lazy load database
let dbInstance: any = null;
function getDb() {
    if (!dbInstance) {
        dbInstance = require('../models/database').default;
    }
    return dbInstance;
}

const { isHouseholdPremium } = require('../utils/premiumHelper');

interface UserRow {
    household_id: string | null;
    last_name: string | null;
    email: string;
}

interface HouseholdRow {
    id: string;
    name: string;
    is_premium: number;
    owner_id: string | null;
}

interface InviteCodeRow {
    id: string;
    household_id: string;
    code: string;
    created_by: string;
    expires_at: string;
    used_by: string | null;
    used_at: string | null;
    household_name: string;
}

interface MemberRow {
    id: string;
    email: string;
    first_name: string | null;
    last_name: string | null;
    created_at: string;
}

/**
 * Create default storage locations for a household (DEPRECATED - now client-managed)
 */
function createDefaultLocations(householdId: string): void {
    console.log('⚠️ [Deprecated] createDefaultLocations called - locations are now client-managed');
}

/**
 * Create a new household
 */
function createHousehold(userId: string, name?: string): { id: string; name: string; isPremium: boolean } {
    const db = getDb();
    
    // Check if user already has a household
    const user = db.prepare('SELECT household_id, last_name, email FROM users WHERE id = ?').get(userId) as UserRow;
    if (user.household_id) {
        throw new Error('User already belongs to a household');
    }

    // Generate default name if not provided
    if (!name) {
        if (user.last_name && user.last_name.trim()) {
            name = `${user.last_name} Household`;
        } else if (user.email) {
            const emailName = user.email.split('@')[0];
            const parts = emailName.split(/[._-]/);
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
        db.prepare('INSERT INTO households (id, name, owner_id) VALUES (?, ?, ?)').run(householdId, name, userId);
        db.prepare('UPDATE users SET household_id = ? WHERE id = ?').run(householdId, userId);
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
 */
function generateInviteCode(householdId: string | null, userId: string): { code: string; expiresAt: string; householdName: string } {
    const db = getDb();
    
    if (!householdId) {
        throw new Error('User does not belong to a household');
    }
    
    const household = db.prepare('SELECT is_premium, name FROM households WHERE id = ?').get(householdId) as HouseholdRow;
    if (!household.is_premium) {
        const error: any = new Error('Household sharing is a Premium feature');
        error.code = 'PREMIUM_REQUIRED';
        throw error;
    }

    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    let code = '';
    for (let i = 0; i < 6; i++) {
        code += chars.charAt(Math.floor(Math.random() * chars.length));
    }

    const id = uuidv4();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();

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
 */
function validateInviteCode(code: string): { valid: boolean; householdId: string; householdName: string; memberCount: number; expiresAt: string } {
    const db = getDb();
    
    const invite = db.prepare(`
        SELECT ic.*, h.name as household_name
        FROM invite_codes ic
        JOIN households h ON ic.household_id = h.id
        WHERE ic.code = ? AND ic.used_by IS NULL AND ic.expires_at > datetime('now')
    `).get(code.toUpperCase()) as InviteCodeRow | undefined;

    if (!invite) {
        throw new Error('Invalid or expired invite code');
    }

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
 */
function joinHousehold(userId: string, code: string): { success: boolean; household: { id: string; name: string } } {
    const db = getDb();
    
    const invite = db.prepare(`
        SELECT * FROM invite_codes
        WHERE code = ? AND used_by IS NULL AND expires_at > datetime('now')
    `).get(code.toUpperCase()) as InviteCodeRow | undefined;

    if (!invite) {
        throw new Error('Invalid or expired invite code');
    }

    const currentMembers = db.prepare('SELECT COUNT(*) as count FROM users WHERE household_id = ?')
        .get(invite.household_id).count;

    if (currentMembers >= 8) {
        const error: any = new Error('This household has reached the maximum of 8 members');
        error.code = 'MEMBER_LIMIT_REACHED';
        throw error;
    }

    db.prepare('UPDATE users SET household_id = ?, updated_at = ? WHERE id = ?')
        .run(invite.household_id, new Date().toISOString(), userId);

    db.prepare('UPDATE invite_codes SET used_by = ?, used_at = ? WHERE id = ?')
        .run(userId, new Date().toISOString(), invite.id);

    const household = db.prepare('SELECT * FROM households WHERE id = ?').get(invite.household_id) as HouseholdRow;

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
 */
function getHouseholdMembers(householdId: string): any[] {
    const db = getDb();
    
    const household = db.prepare('SELECT owner_id FROM households WHERE id = ?').get(householdId) as { owner_id: string | null } | undefined;
    const ownerId = household?.owner_id;

    const members = db.prepare(`
        SELECT id, email, first_name, last_name, created_at
        FROM users
        WHERE household_id = ?
        ORDER BY created_at ASC
    `).all(householdId) as MemberRow[];

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
 */
function getActiveInviteCodes(householdId: string): any[] {
    const db = getDb();
    
    const invites = db.prepare(`
        SELECT code, expires_at, created_at
        FROM invite_codes
        WHERE household_id = ? AND used_by IS NULL AND expires_at > datetime('now')
        ORDER BY created_at DESC
    `).all(householdId);

    return invites;
}

/**
 * Reset household data
 */
function resetHouseholdData(householdId: string, userId: string): { success: boolean; message: string } {
    const db = getDb();
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

        createDefaultLocations(householdId);
        console.log(`🗑️ [Reset] Re-created default locations`);
    });

    transaction();
    console.log(`✅ [Reset] Transaction completed for household ${householdId}`);

    return { success: true, message: 'Household data reset successfully' };
}

export default {
    createDefaultLocations,
    createHousehold,
    generateInviteCode,
    validateInviteCode,
    joinHousehold,
    getHouseholdMembers,
    getActiveInviteCodes,
    resetHouseholdData
};
