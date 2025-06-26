#!/bin/bash
# reset_warpnest.sh - Reset all WarpNest (Multi-WARP VPN Manager) state

set -e

INSTALL_DIR="/opt/warp-manager"
if [ ! -d "$INSTALL_DIR" ]; then
  INSTALL_DIR="$HOME/warp-manager"
fi

# Read base port from config file if present
CONFIG_FILE="$INSTALL_DIR/warp_manager.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# Confirm reset
read -p "This will remove all WARP profiles, flush iptables rules, remove supervisor configs, and restart everything. Continue? [y/N]: " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo -e "\033[1;33mAborted.\033[0m"
  exit 0
fi

echo -e "\033[1;33mStopping warp-manager service...\033[0m"
systemctl stop warp-manager || true

# Remove all WARP profiles and namespaces
echo -e "\033[1;33mRemoving WARP profiles and namespaces...\033[0m"
if [ -d "$HOME/warp-profiles" ]; then
  ip -all netns delete || true
  rm -rf "$HOME/warp-profiles"
fi

# Use BASE_PORT from config if set, otherwise prompt
if [ -z "$BASE_PORT" ]; then
  read -p "Enter starting port for SOCKS proxies [default: 1080]: " BASE_PORT
  BASE_PORT=${BASE_PORT:-1080}
fi
echo -e "\033[1;33mSOCKS proxies will start from port $BASE_PORT.\033[0m"

# Flush iptables rules for only the 64 possible proxy ports
if command -v iptables >/dev/null 2>&1; then
  for port in $(seq $BASE_PORT $((BASE_PORT+63))); do
    iptables -D INPUT -p tcp --dport $port -j ACCEPT 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp --dport $port -j DNAT 2>/dev/null || true
  done
fi

# Remove supervisor configs (if any)
echo -e "\033[1;33mRemoving supervisor configs...\033[0m"
if [ -d "/etc/supervisor/conf.d" ]; then
  rm -f /etc/supervisor/conf.d/warp*.conf || true
  supervisorctl reread || true
  supervisorctl update || true
fi

# Optionally remove systemd service
echo -e "\033[1;33mRemoving systemd service...\033[0m"
systemctl disable warp-manager || true
rm -f /etc/systemd/system/warp-manager.service || true
systemctl disable restore_warpnet || true
rm -f /etc/systemd/system/restore_warpnet.service || true
systemctl daemon-reload || true

# Re-run installer
echo -e "\033[1;33mRe-running installer to recreate everything...\033[0m"
bash "$INSTALL_DIR/install_warp_manager.sh"
