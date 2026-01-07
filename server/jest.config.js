module.exports = {
    testEnvironment: 'node',
    testTimeout: 10000,
    verbose: true,
    testMatch: [
        '**/tests/e2e/**/*.test.js',
        '**/tests/**/*.test.js'
    ],
    // Detect open handles (database connections, timers, etc.)
    detectOpenHandles: true,
    forceExit: false,
    // Coverage configuration
    coverageDirectory: 'coverage',
    coveragePathIgnorePatterns: [
        '/node_modules/',
        '/tests/'
    ],
    // Setup/teardown
    globalSetup: './tests/setup/globalSetup.js',
    globalTeardown: './tests/setup/globalTeardown.js',
};
