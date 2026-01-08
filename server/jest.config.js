module.exports = {
	preset: 'ts-jest/presets/js-with-ts',
	testEnvironment: 'node',
	testTimeout: 10000,
	verbose: true,
	testMatch: [
		'**/tests/e2e/**/*.test.js',
		'**/tests/**/*.test.js'
	],
	// TypeScript support with relaxed checking for tests
	transform: {
		'^.+\\.tsx?$': ['ts-jest', {
			tsconfig: {
				module: 'commonjs',
				esModuleInterop: true,
				allowSyntheticDefaultImports: true,
				noUnusedLocals: false,
				noUnusedParameters: false,
				strict: false
			},
			// Skip type checking entirely for faster test runs
			isolatedModules: true,
			diagnostics: false
		}],
		'^.+\\.jsx?$': 'babel-jest'
	},
	moduleFileExtensions: ['ts', 'tsx', 'js', 'jsx', 'json', 'node'],
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
