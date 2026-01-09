#!/bin/bash

# Reset PantryPal Database
# This script removes the Docker volume and recreates the database with fresh schema
# Usage: ./reset-database.sh [--force]

set -e

# Parse arguments
FORCE=false
if [ "$1" = "--force" ] || [ "$1" = "-f" ]; then
    FORCE=true
fi

echo "🔄 Resetting PantryPal database..."
echo "⚠️  WARNING: This will delete ALL data!"

if [ "$FORCE" = false ]; then
    read -p "Are you sure? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "❌ Aborted"
        exit 1
    fi
else
    echo "⚠️  Force mode enabled, skipping confirmation"
fi

echo ""
echo "📦 Stopping containers and removing volumes..."
ssh root@62.146.177.62 "cd /root/pantrypal-server/server && docker compose down -v"

echo ""
echo "🧹 Cleaning up any orphaned volumes..."
ssh root@62.146.177.62 "docker volume prune -f | grep -E '(pantrypal|Total)' || echo 'No orphaned volumes found'"

echo ""
echo "🚀 Starting containers with fresh database..."
ssh root@62.146.177.62 "cd /root/pantrypal-server/server && docker compose up -d"

echo ""
echo "🔗 Connecting to nginx network..."
ssh root@62.146.177.62 "docker network connect web server-pantrypal-api-1 2>&1 || echo 'Already connected'"

echo ""
echo "⏳ Waiting for database initialization..."
sleep 5

echo ""
echo "✅ Checking database status..."
ssh root@62.146.177.62 "cd /root/pantrypal-server/server && docker compose logs --tail=10 pantrypal-api | grep -E '(Database|initialized|running)'"

echo ""
echo "✅ Database reset complete!"
echo "🔗 API: https://api-pantrypal.subasically.me"
echo "🔗 Health: https://api-pantrypal.subasically.me/health"
