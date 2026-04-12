#!/bin/bash
# AASTAR Relay Restart Script
# Pulls latest code and restarts the relay

set -e

echo "=============================================="
echo "  AASTAR Relay Restart"
echo "=============================================="
echo ""

cd "$(dirname "$0")"

echo "[1/4] Pulling latest code..."
git pull origin agent-speaker

echo ""
echo "[2/4] Stopping existing container..."
docker-compose -f docker-compose.aastar.yml down

echo ""
echo "[3/4] Starting relay..."
docker-compose -f docker-compose.aastar.yml up -d

echo ""
echo "[4/4] Waiting for relay to start..."
sleep 2

echo ""
echo "Testing relay..."
if curl -s http://localhost:7777 > /dev/null; then
    echo "✅ Relay is running!"
    curl -s http://localhost:7777 | head -20
else
    echo "❌ Relay not responding, checking logs..."
    docker-compose -f docker-compose.aastar.yml logs --tail=20
fi

echo ""
echo "=============================================="
echo "  Restart Complete"
echo "=============================================="
