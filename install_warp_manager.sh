#!/bin/bash
# Install and setup warp-manager and dependencies from scratch

set -e

echo "Updating system and installing dependencies..."
apt install -y python3 python3-pip python3-venv supervisor wireguard-tools iproute2 curl nftables

echo "Installing wgcf..."
if ! command -v wgcf >/dev/null 2>&1; then
  wget -qO wgcf https://github.com/ViRb3/wgcf/releases/download/v2.2.26/wgcf_2.2.26_linux_amd64
  chmod +x wgcf && mv wgcf /usr/local/bin/
fi

# Prompt user for install directory if /opt/warp-manager is not writable
DEFAULT_INSTALL_DIR="/opt/warp-manager"
# Use SOURCE_DIR if provided, otherwise fall back to script location
if [ -n "$SOURCE_DIR" ]; then
  SCRIPT_DIR="$SOURCE_DIR"
  echo "Using source directory from environment: $SCRIPT_DIR"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  echo "Script directory is: $SCRIPT_DIR"
fi

if mkdir -p "$DEFAULT_INSTALL_DIR" 2>/dev/null; then
  chown $USER:$USER "$DEFAULT_INSTALL_DIR"
  INSTALL_DIR="$DEFAULT_INSTALL_DIR"
  echo "Setting up install directory at $INSTALL_DIR..."
else
  echo "[WARNING] Could not create $DEFAULT_INSTALL_DIR."
  read -p "Enter an alternative install directory [default: $HOME/warp-manager]: " USER_INSTALL_DIR
  INSTALL_DIR="${USER_INSTALL_DIR:-$HOME/warp-manager}"
  mkdir -p "$INSTALL_DIR"
  echo "Setting up install directory at $INSTALL_DIR..."
fi

# Copy all scripts, Python files, and UI templates from installer/
echo "Copying scripts and UI files from installer..."
cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR"/

# Set up Python virtual environment for Flask UI
echo "Setting up Python virtual environment for warp-manager UI..."
cd "$INSTALL_DIR"
python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip
pip install flask psutil werkzeug

# Ensure templates directory exists and is correct
if [ ! -d "$INSTALL_DIR/templates" ]; then
  echo "templates directory not found in $INSTALL_DIR, creating it..."
  mkdir -p "$INSTALL_DIR/templates"
  # Try to copy from source if available
  if [ -d "$SCRIPT_DIR/templates" ]; then
    cp -r "$SCRIPT_DIR/templates/." "$INSTALL_DIR/templates/"
    echo "Copied templates from $SCRIPT_DIR/templates."
  else
    echo "WARNING: No source templates directory found. UI may not function correctly."
  fi
fi

# Step 1: Create WARP profiles
read -p "Do you want to create WARP profiles now (run config_vnc.sh)? [Y/n]: " RUN_CONFIG_VNC
if [[ ! "$RUN_CONFIG_VNC" =~ ^[Nn]$ ]]; then
  if [ -x "$INSTALL_DIR/config_vnc.sh" ]; then
    echo "Running $INSTALL_DIR/config_vnc.sh..."
    bash "$INSTALL_DIR/config_vnc.sh"
  else
    echo "[WARNING] $INSTALL_DIR/config_vnc.sh not found or not executable. Skipping."
  fi
else
  echo "Skipping config_vnc.sh. You can run it later with: bash $INSTALL_DIR/config_vnc.sh"
fi

# Step 2: Create supervisor profiles
read -p "Do you want to create supervisor profiles now (run init_supervisor_profiles.sh)? [Y/n]: " RUN_INIT_SUP
if [[ ! "$RUN_INIT_SUP" =~ ^[Nn]$ ]]; then
  if [ -x "$INSTALL_DIR/init_supervisor_profiles.sh" ]; then
    echo "Running $INSTALL_DIR/init_supervisor_profiles.sh..."
    INSTALL_DIR="$INSTALL_DIR" bash "$INSTALL_DIR/init_supervisor_profiles.sh"
  else
    echo "[WARNING] $INSTALL_DIR/init_supervisor_profiles.sh not found or not executable. Skipping."
  fi
else
  echo "Skipping init_supervisor_profiles.sh. You can run it later with: bash $INSTALL_DIR/init_supervisor_profiles.sh"
fi

# Step 3: Generate Dante configs for all proxies
if [ -x "$INSTALL_DIR/danted_config.sh" ]; then
  echo "Generating Dante configs for all proxies..."
  INSTALL_DIR="$INSTALL_DIR" bash "$INSTALL_DIR/danted_config.sh"
else
  echo "[WARNING] $INSTALL_DIR/danted_config.sh not found or not executable. Skipping Dante config generation."
fi

# Step 4: Create systemd service for warp-manager UI
echo "Creating systemd service for warp-manager UI..."
tee /etc/systemd/system/warp-manager.service > /dev/null <<EOF
[Unit]
Description=WARP Manager Flask UI
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=sudo $INSTALL_DIR/venv/bin/python $INSTALL_DIR/dante_manager.py
Restart=always

[Install]
WantedBy=multi-user.target
EOF

echo "Reloading systemd and enabling warp-manager UI..."
systemctl daemon-reload
systemctl enable warp-manager
systemctl restart warp-manager

echo -e "\033[1;33mDone. The WARP Manager UI should be running on port 5010.\033[0m"
echo -e "\033[1;33mYou can access it at http://<your-server-ip>:5010/\033[0m"


# Step 5: Create restore_warpnet service
echo "Creating restore_warpnet service to restore WARP network namespaces and WireGuard after boot..."
tee /etc/systemd/system/restore_warpnet.service > /dev/null <<EOF
[Unit]
Description=Restore WARP network namespaces and iptables after boot
After=network.target

[Service]
Type=oneshot
ExecStart=/bin/bash /opt/warp-manager/restore_warpnet.sh
RemainAfterExit=true

[Install]
WantedBy=multi-user.target
EOF
echo "Reloading systemd and enabling restore_warpnet service..."
systemctl daemon-reload
systemctl enable restore_warpnet
systemctl start restore_warpnet
echo -e "\033[1;33mDone. The restore_warpnet service is set up to run after boot.\033[0m"