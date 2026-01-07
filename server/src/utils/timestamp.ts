/**
 * Timestamp conversion utilities for ISO 8601 ↔ SQLite formats
 * 
 * SQLite stores timestamps as: "YYYY-MM-DD HH:MM:SS"
 * JavaScript/iOS uses ISO 8601: "YYYY-MM-DDTHH:MM:SSZ"
 */

/**
 * Convert ISO 8601 timestamp to SQLite format
 * @param isoTimestamp - ISO 8601 timestamp (e.g., "2026-01-07T18:48:30Z")
 * @returns SQLite timestamp (e.g., "2026-01-07 18:48:30")
 */
export function toSQLite(isoTimestamp: string): string {
    return isoTimestamp
        .replace('T', ' ')
        .replace('Z', '')
        .replace(/\.\d+$/, ''); // Remove milliseconds if present
}

/**
 * Convert SQLite timestamp to ISO 8601 format
 * @param sqliteTimestamp - SQLite timestamp (e.g., "2026-01-07 18:48:30")
 * @returns ISO 8601 timestamp (e.g., "2026-01-07T18:48:30Z")
 */
export function toISO(sqliteTimestamp: string): string {
    return sqliteTimestamp.replace(' ', 'T') + 'Z';
}

/**
 * Get current timestamp in SQLite format
 * @returns Current timestamp as "YYYY-MM-DD HH:MM:SS"
 */
export function now(): string {
    return toSQLite(new Date().toISOString());
}

/**
 * Get current timestamp in ISO format
 * @returns Current timestamp as ISO 8601 string
 */
export function nowISO(): string {
    return new Date().toISOString();
}

/**
 * Parse timestamp (handles both ISO and SQLite formats)
 * @param timestamp - Timestamp in either format
 * @returns Date object
 */
export function parse(timestamp: string): Date {
    // If it contains 'T', it's ISO format
    if (timestamp.includes('T')) {
        return new Date(timestamp);
    }
    // Otherwise, treat as SQLite format
    return new Date(timestamp.replace(' ', 'T') + 'Z');
}

/**
 * Check if timestamp is valid
 * @param timestamp - Timestamp to validate
 * @returns True if valid timestamp
 */
export function isValid(timestamp: string): boolean {
    const date = parse(timestamp);
    return !isNaN(date.getTime());
}
