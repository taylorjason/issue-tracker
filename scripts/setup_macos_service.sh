#!/usr/bin/env bash
# macOS Service Manager for Nova Tracker
# Automates the Launch Agent setup and lifecycle

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PLIST_NAME="com.nova.tracker.plist"
PLIST_TEMPLATE="$SCRIPT_DIR/$PLIST_NAME"
TARGET_PLIST="$HOME/Library/LaunchAgents/$PLIST_NAME"
NODE_PATH="$(which node)"
SERVER_SCRIPT="$SCRIPT_DIR/server.mjs"

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
  echo "Usage: $0 [install|uninstall|status|restart|logs]"
  echo "  install    — Install and start the background service"
  echo "  uninstall  — Stop and remove the background service"
  echo "  status     — Check if the service is running"
  echo "  restart    — Restart the service"
  echo "  logs       — View recent server logs"
  exit 1
}

if [ $# -lt 1 ]; then usage; fi
CMD=$1

# ── Commands ──────────────────────────────────────────────────────────────────
case "$CMD" in
  install)
    echo "[Nova Service] Installing service..."
    
    # 1. Substitute placeholders in plist
    sed -e "s|{{NODE_PATH}}|$NODE_PATH|g" \
        -e "s|{{SERVER_SCRIPT_PATH}}|$SERVER_SCRIPT|g" \
        -e "s|{{REPO_ROOT}}|$REPO_ROOT|g" \
        "$PLIST_TEMPLATE" > "$TARGET_PLIST"
    
    # 2. Set permissions (not strictly necessary for user LaunchAgents, but good practice)
    chmod 644 "$TARGET_PLIST"
    
    # 3. Unload existing if any, then load (bootstrap)
    launchctl bootout gui/$(id -u) "$TARGET_PLIST" 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$TARGET_PLIST"
    
    echo "[Nova Service] Service installed and started: $TARGET_PLIST"
    echo "[Nova Service] Logs: $REPO_ROOT/nova_server.log"
    ;;

  uninstall)
    echo "[Nova Service] Uninstalling service..."
    launchctl bootout gui/$(id -u) "$TARGET_PLIST" 2>/dev/null || true
    rm -f "$TARGET_PLIST"
    echo "[Nova Service] Service uninstalled."
    ;;

  status)
    echo "[Nova Service] Checking status..."
    if launchctl list | grep -q "com.nova.tracker"; then
      echo "[Nova Service] Status: RUNNING"
      # Show the PID
      launchctl list "com.nova.tracker" | grep "PID" || true
    else
      echo "[Nova Service] Status: NOT RUNNING"
    fi
    ;;

  restart)
    echo "[Nova Service] Restarting service..."
    launchctl bootout gui/$(id -u) "$TARGET_PLIST" 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$TARGET_PLIST"
    echo "[Nova Service] Service restarted."
    ;;

  logs)
    echo "[Nova Service] Recent logs:"
    tail -n 20 "$REPO_ROOT/nova_server.log"
    ;;

  *)
    usage
    ;;
esac
