// Lazy load database
let dbInstance: any = null;
function getDb() {
	if (!dbInstance) {
		dbInstance = require('../models/database').default;
	}
	return dbInstance;
}

import logger from './logger';

export const FREE_LIMIT = 25;

interface HouseholdRow {
	is_premium: number;
	premium_expires_at: string | null;
}

interface PremiumInfo {
	isPremium: boolean;
	premiumExpiresAt: string | null;
	isActive: boolean;
}

/**
 * Check if a household has active Premium status
 */
export function isHouseholdPremium(householdId: string): boolean {
	const db = getDb();
	const household = db.prepare(`
        SELECT is_premium, premium_expires_at 
        FROM households 
        WHERE id = ?
    `).get(householdId) as HouseholdRow | undefined;

	if (!household || !household.is_premium) {
		logger.logPremium('premium_check', {
			householdId,
			isPremium: false,
			reason: household ? 'not_premium' : 'household_not_found'
		});
		return false;
	}

	if (!household.premium_expires_at) {
		logger.logPremium('premium_check', {
			householdId,
			isPremium: true,
			expiresAt: null
		});
		return true;
	}

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
 * Check if household can add more items
 */
export function canAddItems(householdId: string, currentCount: number): boolean {
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
 * Check if household is over the free limit
 */
export function isOverFreeLimit(householdId: string, currentCount: number): boolean {
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
export function getHouseholdPremiumInfo(householdId: string): PremiumInfo {
	const db = getDb();
	const household = db.prepare(`
        SELECT is_premium, premium_expires_at 
        FROM households 
        WHERE id = ?
    `).get(householdId) as HouseholdRow | undefined;

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

export default {
	FREE_LIMIT,
	isHouseholdPremium,
	canAddItems,
	isOverFreeLimit,
	getHouseholdPremiumInfo
};
