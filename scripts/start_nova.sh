#!/usr/bin/env bash
# Nova Launcher — start_nova.sh
# macOS/Linux script
# Starts the Node.js server, then opens the browser to http://127.0.0.1:1414.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
SERVER_SCRIPT="$SCRIPT_DIR/server.mjs"

PORT="1515"

# ── Start server ──────────────────────────────────────────────────────────────
echo "[Nova Launcher] Starting server on port $PORT..."
TRACKER_PORT="$PORT" \
TRACKER_DIST_DIR="$REPO_ROOT" \
TRACKER_DATA_DIR="$SCRIPT_DIR/data" \
  node "$SERVER_SCRIPT" &

SERVER_PID=$!
echo "[Nova Launcher] Server PID: $SERVER_PID"

# ── Open browser after brief delay ────────────────────────────────────────────
sleep 1

echo "[Nova Launcher] Opening http://127.0.0.1:$PORT ..."
if command -v open &>/dev/null; then
  open "http://127.0.0.1:$PORT"          # macOS
elif command -v xdg-open &>/dev/null; then
  xdg-open "http://127.0.0.1:$PORT"     # Linux
else
  echo "[Nova Launcher] Open your browser to: http://127.0.0.1:$PORT"
fi

# ── Keep running (Ctrl+C stops the server) ────────────────────────────────────
echo "[Nova Launcher] Press Ctrl+C to stop the server."
wait $SERVER_PID
