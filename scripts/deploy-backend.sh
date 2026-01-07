#!/bin/bash

# PantryPal Backend Deployment Script
# Deploys code changes to production server and rebuilds Docker containers
# Usage: ./scripts/deploy-backend.sh [options]
#   Options:
#     --restart-only    Just restart without rebuild (faster, but won't pick up code changes)
#     --no-verify       Skip health check after deployment
#     --logs            Show logs after deployment

set -e  # Exit on error

# Configuration
SERVER_USER="root"
SERVER_HOST="62.146.177.62"
SERVER_PATH="/root/pantrypal-server"
LOCAL_SERVER_PATH="./server"
HEALTH_CHECK_URL="https://api-pantrypal.subasically.me/health"
HEALTH_CHECK_RETRIES=10
HEALTH_CHECK_DELAY=3

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Parse arguments
RESTART_ONLY=false
NO_VERIFY=false
SHOW_LOGS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --restart-only)
            RESTART_ONLY=true
            shift
            ;;
        --no-verify)
            NO_VERIFY=true
            shift
            ;;
        --logs)
            SHOW_LOGS=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Usage: $0 [--restart-only] [--no-verify] [--logs]"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}   PantryPal Backend Deployment${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Step 1: Verify local changes
echo -e "${YELLOW}[1/6] Checking for uncommitted changes...${NC}"
if [[ -n $(git status --porcelain server/) ]]; then
    echo -e "${YELLOW}⚠️  Warning: You have uncommitted changes in server/:"
    git status --short server/
    echo ""
    read -p "Continue deployment? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}Deployment cancelled${NC}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ No uncommitted changes${NC}"
fi
echo ""

# Step 2: Sync code to server
echo -e "${YELLOW}[2/6] Syncing code to production server...${NC}"
rsync -avz --delete \
    --exclude 'node_modules' \
    --exclude 'db/pantrypal.db*' \
    --exclude '.env' \
    --exclude 'logs/' \
    ${LOCAL_SERVER_PATH}/ ${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}/
echo -e "${GREEN}✓ Code synced${NC}"
echo ""

# Step 3: Deploy
if [ "$RESTART_ONLY" = true ]; then
    echo -e "${YELLOW}[3/6] Restarting containers (no rebuild)...${NC}"
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH} && docker-compose restart pantrypal-api"
    echo -e "${YELLOW}⚠️  Note: restart does not pick up code changes. Use full rebuild for code updates.${NC}"
else
    echo -e "${YELLOW}[3/6] Rebuilding and restarting containers...${NC}"
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH} && docker-compose up -d --build --force-recreate"
    echo -e "${GREEN}✓ Containers rebuilt and started${NC}"
fi
echo ""

# Step 4: Wait for container to be ready
echo -e "${YELLOW}[4/6] Waiting for container to start...${NC}"
sleep 5
echo -e "${GREEN}✓ Container should be running${NC}"
echo ""

# Step 5: Health check
if [ "$NO_VERIFY" = false ]; then
    echo -e "${YELLOW}[5/6] Verifying API health...${NC}"
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $HEALTH_CHECK_RETRIES ]; do
        if curl -f -s ${HEALTH_CHECK_URL} > /dev/null 2>&1; then
            HEALTH_RESPONSE=$(curl -s ${HEALTH_CHECK_URL})
            echo -e "${GREEN}✓ API is healthy!${NC}"
            echo "   Response: $HEALTH_RESPONSE"
            break
        else
            RETRY_COUNT=$((RETRY_COUNT + 1))
            if [ $RETRY_COUNT -eq $HEALTH_CHECK_RETRIES ]; then
                echo -e "${RED}✗ Health check failed after $HEALTH_CHECK_RETRIES attempts${NC}"
                echo -e "${RED}API may not be responding correctly${NC}"
                echo ""
                echo -e "${YELLOW}Recent logs:${NC}"
                ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH} && docker-compose logs --tail=20 pantrypal-api"
                exit 1
            fi
            echo "   Attempt $RETRY_COUNT/$HEALTH_CHECK_RETRIES failed, retrying in ${HEALTH_CHECK_DELAY}s..."
            sleep $HEALTH_CHECK_DELAY
        fi
    done
else
    echo -e "${YELLOW}[5/6] Skipping health check (--no-verify)${NC}"
fi
echo ""

# Step 6: Show logs (optional)
if [ "$SHOW_LOGS" = true ]; then
    echo -e "${YELLOW}[6/6] Recent logs:${NC}"
    ssh ${SERVER_USER}@${SERVER_HOST} "cd ${SERVER_PATH} && docker-compose logs --tail=30 pantrypal-api"
else
    echo -e "${YELLOW}[6/6] Deployment complete${NC}"
    echo "   Tip: Use --logs flag to see recent logs"
fi
echo ""

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}   ✓ Deployment successful!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "API URL: ${HEALTH_CHECK_URL}"
echo ""
echo "Useful commands:"
echo "  View logs:         ssh ${SERVER_USER}@${SERVER_HOST} 'cd ${SERVER_PATH} && docker-compose logs -f pantrypal-api'"
echo "  Restart only:      ./scripts/deploy-backend.sh --restart-only"
echo "  Check health:      curl ${HEALTH_CHECK_URL}"
echo "  SSH to server:     ssh ${SERVER_USER}@${SERVER_HOST}"
echo ""
