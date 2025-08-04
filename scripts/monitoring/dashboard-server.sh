#!/bin/bash
# Quick Dashboard Server for Development Monitoring
# This serves the monitoring dashboard on a separate port

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DASHBOARD_FILE="$PROJECT_ROOT/monitoring/dashboard.html"
PORT="${1:-3000}"

echo "Starting monitoring dashboard server on port $PORT..."
echo "Dashboard file: $DASHBOARD_FILE"
echo "Access at: http://localhost:$PORT"
echo ""

if [ ! -f "$DASHBOARD_FILE" ]; then
    echo "Error: Dashboard file not found at $DASHBOARD_FILE"
    exit 1
fi

# Start a simple HTTP server
cd "$PROJECT_ROOT/monitoring"

if command -v python3 &> /dev/null; then
    echo "Using Python 3 HTTP server..."
    python3 -m http.server "$PORT"
elif command -v python &> /dev/null; then
    echo "Using Python HTTP server..."
    python -m SimpleHTTPServer "$PORT"
elif command -v node &> /dev/null; then
    echo "Using Node.js HTTP server..."
    npx http-server -p "$PORT" -c-1
else
    echo "Error: No suitable HTTP server found. Please install Python or Node.js."
    exit 1
fi
