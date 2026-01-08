/**
 * Jest global setup
 * Runs once before all tests
 */

module.exports = async () => {
	console.log('\n🚀 Starting test suite...\n');

	// Set test environment variables
	process.env.NODE_ENV = 'test';
	process.env.JWT_SECRET = 'test-secret-key-for-jest';

	// Disable rate limiting in tests
	process.env.RATE_LIMIT_ENABLED = 'false';
};
