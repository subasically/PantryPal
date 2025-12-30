const db = require('../models/database');

const FREE_LIMIT = 25;

/**
 * Check if a household has active Premium status
 * Premium is active if:
 * - is_premium == 1 (true) AND
 * - (premium_expires_at is NULL OR premium_expires_at > now)
 */
function isHouseholdPremium(householdId) {
    const household = db.prepare(`
        SELECT is_premium, premium_expires_at 
        FROM households 
        WHERE id = ?
    `).get(householdId);
    
    if (!household || !household.is_premium) {
        return false;
    }
    
    // If no expiration date, Premium is active indefinitely
    if (!household.premium_expires_at) {
        return true;
    }
    
    // Check if expiration date is in the future
    const now = new Date();
    const expiresAt = new Date(household.premium_expires_at);
    
    return expiresAt > now;
}

/**
 * Check if household can add more items (respects Premium and free limits)
 */
function canAddItems(householdId, currentCount) {
    if (isHouseholdPremium(householdId)) {
        return true; // Premium = unlimited
    }
    
    return currentCount < FREE_LIMIT;
}

/**
 * Check if household is over the free limit (for read-only enforcement)
 */
function isOverFreeLimit(householdId, currentCount) {
    if (isHouseholdPremium(householdId)) {
        return false; // Premium never over limit
    }
    
    return currentCount >= FREE_LIMIT;
}

/**
 * Get household Premium info with expiration
 */
function getHouseholdPremiumInfo(householdId) {
    const household = db.prepare(`
        SELECT is_premium, premium_expires_at 
        FROM households 
        WHERE id = ?
    `).get(householdId);
    
    if (!household) {
        return {
            isPremium: false,
            premiumExpiresAt: null,
            isActive: false
        };
    }
    
    const isPremium = !!household.is_premium;
    const premiumExpiresAt = household.premium_expires_at;
    const isActive = isHouseholdPremium(householdId);
    
    return {
        isPremium,
        premiumExpiresAt,
        isActive
    };
}

module.exports = {
    FREE_LIMIT,
    isHouseholdPremium,
    canAddItems,
    isOverFreeLimit,
    getHouseholdPremiumInfo
};
