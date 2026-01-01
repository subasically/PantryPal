# Test Server Setup with Docker

## Local Test Environment

This setup creates an isolated test server for UI testing without touching production.

### Prerequisites
- Docker Desktop installed and running
- Ports 3002 available (or modify below)

---

## Option 1: Docker Compose (Recommended)

### 1. Create Test Environment File

```bash
cd server
cat > .env.test << 'EOF'
PORT=3002
JWT_SECRET=test-secret-change-me
NODE_ENV=test
ALLOW_TEST_ENDPOINTS=true
TEST_ADMIN_KEY=pantrypal-test-key-2025
FREE_LIMIT=25
EOF
```

### 2. Create Test Docker Compose

```yaml
# server/docker-compose.test.yml
version: '3.8'

services:
  test-api:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: pantrypal-test-api
    ports:
      - "3002:3002"
    env_file:
      - .env.test
    volumes:
      - test-db:/app/db
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3002/health"]
      interval: 10s
      timeout: 5s
      retries: 3

volumes:
  test-db:
    driver: local
```

### 3. Start Test Server

```bash
cd server
docker-compose -f docker-compose.test.yml up -d

# Wait for health check
sleep 5

# Verify it's running
curl http://localhost:3002/health
curl http://localhost:3002/api/test/status -H "x-test-admin-key: pantrypal-test-key-2025"
```

### 4. Stop Test Server

```bash
cd server
docker-compose -f docker-compose.test.yml down

# Optional: Remove test database
docker-compose -f docker-compose.test.yml down -v
```

---

## Option 2: Quick Local Server (Development)

### 1. Install Dependencies

```bash
cd server
npm install
```

### 2. Start Test Server

```bash
cd server
NODE_ENV=test \
ALLOW_TEST_ENDPOINTS=true \
TEST_ADMIN_KEY=pantrypal-test-key-2025 \
PORT=3002 \
npm start
```

### 3. In Another Terminal: Run UI Tests

```bash
cd ios
xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,id=DEA4C9CE-5106-41AD-B36A-378A8714D172' \
  -only-testing:PantryPalUITests
```

---

## Option 3: NPM Script (Easiest)

### 1. Add to `server/package.json`:

```json
{
  "scripts": {
    "start": "node src/index.js",
    "dev": "nodemon src/index.js",
    "test:server": "NODE_ENV=test ALLOW_TEST_ENDPOINTS=true TEST_ADMIN_KEY=pantrypal-test-key-2025 PORT=3002 node src/index.js"
  }
}
```

### 2. Run Test Server

```bash
cd server
npm run test:server
```

### 3. Run UI Tests (in another terminal)

```bash
cd ios
xcodebuild test -scheme PantryPal \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:PantryPalUITests
```

---

## Verification Steps

### 1. Check Test Server Health

```bash
# Basic health check
curl http://localhost:3002/health

# Test endpoints status
curl http://localhost:3002/api/test/status \
  -H "x-test-admin-key: pantrypal-test-key-2025"

# Seed test data
curl -X POST http://localhost:3002/api/test/seed \
  -H "x-test-admin-key: pantrypal-test-key-2025"

# Get credentials
curl http://localhost:3002/api/test/credentials \
  -H "x-test-admin-key: pantrypal-test-key-2025"
```

### 2. Test Login Flow

```bash
curl -X POST http://localhost:3002/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@pantrypal.com","password":"Test123!"}'
```

---

## UI Test Configuration

Your UI tests are already configured for `localhost:3002`:

```swift
// ios/PantryPalUITests/PantryPalUITests.swift
let testServerURL = "http://localhost:3002"
let testAdminKey = "pantrypal-test-key-2025"
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: UI Tests

on: [push, pull_request]

jobs:
  ui-tests:
    runs-on: macos-13
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: '20'
      
      - name: Install Server Dependencies
        run: |
          cd server
          npm ci
      
      - name: Start Test Server
        run: |
          cd server
          NODE_ENV=test \
          ALLOW_TEST_ENDPOINTS=true \
          TEST_ADMIN_KEY=pantrypal-test-key-2025 \
          PORT=3002 \
          npm start &
          
          # Wait for server to be ready
          timeout 30 bash -c 'until curl -f http://localhost:3002/health; do sleep 1; done'
      
      - name: Run UI Tests
        run: |
          cd ios
          xcodebuild test \
            -scheme PantryPal \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -only-testing:PantryPalUITests
```

---

## Recommended Workflow

### For Development

```bash
# Terminal 1: Start test server
cd server && npm run test:server

# Terminal 2: Run tests in Xcode (Cmd+U)
# Or via command line:
cd ios && xcodebuild test -scheme PantryPal -destination '...' -only-testing:PantryPalUITests
```

### For CI/CD

Use Docker Compose for consistency:

```bash
# Start test environment
docker-compose -f server/docker-compose.test.yml up -d

# Run tests
cd ios && xcodebuild test ...

# Cleanup
docker-compose -f server/docker-compose.test.yml down -v
```

---

## Database Isolation

**Test Database:** Each test run should reset the database:

```swift
override func setUpWithError() throws {
    // This resets the local test database
    resetTestServer()
    seedTestServer()
    app.launch()
}
```

**Production Safety:**
- Test server runs on different port (3002)
- Uses separate database file
- Test endpoints require admin key
- No connection to production data

---

## Troubleshooting

### Port Already in Use

```bash
# Find process using port 3002
lsof -i :3002

# Kill it
kill -9 <PID>

# Or use a different port
PORT=3003 npm run test:server
```

### Docker Container Won't Start

```bash
# Check logs
docker logs pantrypal-test-api

# Rebuild from scratch
docker-compose -f docker-compose.test.yml down -v
docker-compose -f docker-compose.test.yml build --no-cache
docker-compose -f docker-compose.test.yml up -d
```

### Tests Can't Connect

```bash
# Verify server is running
curl http://localhost:3002/health

# Check test server URL in tests
grep testServerURL ios/PantryPalUITests/PantryPalUITests.swift

# Verify no firewall blocking localhost
```

---

## Summary

✅ **DO:** Test against local Docker container or `npm run test:server`  
❌ **DON'T:** Test against production API  

**Why?**
- Tests can safely reset/seed database
- No risk of corrupting production data
- Faster test execution (no network latency)
- Tests work offline
- Consistent test environment
