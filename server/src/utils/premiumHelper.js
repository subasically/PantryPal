const db = require('../models/database');
const logger = require('./logger');

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
        logger.logPremium('premium_check', {
            householdId,
            isPremium: false,
            reason: household ? 'not_premium' : 'household_not_found'
        });
        return false;
    }
    
    // If no expiration date, Premium is active indefinitely
    if (!household.premium_expires_at) {
        logger.logPremium('premium_check', {
            householdId,
            isPremium: true,
            expiresAt: null
        });
        return true;
    }
    
    // Check if expiration date is in the future
    const now = new Date();
    const expiresAt = new Date(household.premium_expires_at);
    const isActive = expiresAt > now;
    
    logger.logPremium('premium_check', {
        householdId,
        isPremium: true,
        isActive,
        expiresAt: household.premium_expires_at
    });
    
    return isActive;
}

/**
 * Check if household can add more items (respects Premium and free limits)
 */
function canAddItems(householdId, currentCount) {
    const isPremium = isHouseholdPremium(householdId);
    const canAdd = isPremium || currentCount < FREE_LIMIT;
    
    logger.logPremium('limit_check', {
        householdId,
        isPremium,
        currentCount,
        limit: FREE_LIMIT,
        canAdd
    });
    
    return canAdd;
}

/**
 * Check if household is over the free limit (for read-only enforcement)
 */
function isOverFreeLimit(householdId, currentCount) {
    const isPremium = isHouseholdPremium(householdId);
    const isOver = !isPremium && currentCount >= FREE_LIMIT;
    
    logger.logPremium('over_limit_check', {
        householdId,
        isPremium,
        currentCount,
        limit: FREE_LIMIT,
        isOver
    });
    
    return isOver;
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
