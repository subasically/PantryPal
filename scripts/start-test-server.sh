#!/bin/bash
echo "🚀 Starting PantryPal Test Server..."
cd "$(dirname "$0")/../server" || exit 1
EXISTING_PID=$(lsof -ti:3002 2>/dev/null)
if [ -n "$EXISTING_PID" ]; then
    echo "⚠️  Killing existing server (PID: $EXISTING_PID)..."
    kill "$EXISTING_PID" 2>/dev/null
    sleep 2
fi
echo "▶️  Starting test server..."
npm run test:server > /tmp/pantrypal-test-server.log 2>&1 &
SERVER_PID=$!
sleep 5
if curl -s http://localhost:3002/health > /dev/null 2>&1; then
    echo "✅ Test server running! PID: $SERVER_PID"
    echo "   Stop with: kill $SERVER_PID"
else
    echo "❌ Failed to start"
    exit 1
fi
