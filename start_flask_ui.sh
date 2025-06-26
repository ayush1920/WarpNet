#!/bin/bash
# start_flask_ui.sh - Kill any process on port 5010, then start Flask UI

PORT=5010
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"
VENV_PY="$INSTALL_DIR/venv/bin/python3"
APP_PY="$INSTALL_DIR/dante_manager.py"

# Kill any process using port 5010 on the host only (no netns)
sudo lsof -ti tcp:$PORT | xargs -r sudo kill -9
sleep 1

# Start Flask app
exec "$VENV_PY" "$APP_PY"
