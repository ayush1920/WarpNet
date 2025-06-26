#!/bin/bash
# install.sh - Installer for Warp Manager

set -e
# apt update
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Copy the main script to /usr/local/bin (requires sudo)
echo "Installing Warp Manager..."
sudo mkdir -p /usr/local/bin
sudo cp "$SCRIPT_DIR/install_warp_manager.sh" /usr/local/bin/warp_manager
sudo chmod +x /usr/local/bin/warp_manager

# Make all relevant scripts in the installer directory executable
chmod +x "$SCRIPT_DIR"/*.sh

echo "Installation complete. Running Warp Manager setup..."

# Pass the original source directory to the installer for correct file copying
sudo SOURCE_DIR="$SCRIPT_DIR" /usr/local/bin/warp_manager

# Detect install directory (default or user-specified)
INSTALL_DIR="/opt/warp-manager"
if [ ! -d "$INSTALL_DIR" ]; then
  # Fallback: check for a warp-manager dir in $HOME
  if [ -d "$HOME/warp-manager" ]; then
    INSTALL_DIR="$HOME/warp-manager"
  else
    # Try to detect from /usr/local/bin/warp_manager log output
    INSTALL_DIR=$(grep -oP 'Setting up install directory at \K.*' "$SCRIPT_DIR/install_log.txt" | tail -1)
    [ -z "$INSTALL_DIR" ] && INSTALL_DIR="$SCRIPT_DIR" # fallback
  fi
fi

# Prompt for UI password and set it for the Flask app (after warp_manager sets up Python env)
DEFAULT_PASS="Admin@789"
read -s -p "Set a password for the WarpNest Web UI [default: $DEFAULT_PASS]: " UI_PASS
UI_PASS=${UI_PASS:-$DEFAULT_PASS}
while [ -z "$UI_PASS" ]; do
  echo
  read -s -p "Password cannot be empty. Please enter a password: " UI_PASS
  UI_PASS=${UI_PASS:-$DEFAULT_PASS}
done
echo
$INSTALL_DIR/venv/bin/python3 -c "from werkzeug.security import generate_password_hash; open('$INSTALL_DIR/ui_pass.txt','w').write(generate_password_hash('$UI_PASS'))"

# Generate and save a random Flask secret key
$INSTALL_DIR/venv/bin/python3 -c "import secrets; open('$INSTALL_DIR/flask_secret_key.txt','w').write(secrets.token_urlsafe(32))"

# Print firewall warning after install
printf "\n\033[1;33m⚠️  IMPORTANT: Make sure to open the ports you configured for SOCKS proxies (e.g., 1080-1143) in your VM or cloud firewall to access the proxies.\033[0m\n"
echo "If you do not open these ports, you will not be able to connect to your proxies from outside."