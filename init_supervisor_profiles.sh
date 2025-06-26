#!/bin/bash
# Initialize and configure supervisor for all warpns proxies

set -e

# Install supervisor if not present
if ! command -v supervisorctl >/dev/null 2>&1; then
  echo -e "\033[1;33mInstalling supervisor...\033[0m"
  apt install -y supervisor
fi

# Enable and start supervisor service
systemctl enable supervisor
systemctl start supervisor

# Set WARP_DIR to match the install location (where config_vnc.sh creates profiles)
if [ -z "$INSTALL_DIR" ]; then
  if [ -f "$CONFIG_FILE" ]; then
    INSTALL_DIR=$(dirname "$CONFIG_FILE")
  elif [ -d "/opt/warp-manager/warp-profiles" ]; then
    INSTALL_DIR="/opt/warp-manager"
  elif [ -d "$HOME/warp-manager/warp-profiles" ]; then
    INSTALL_DIR="$HOME/warp-manager"
  fi
fi
WARP_DIR="$INSTALL_DIR/warp-profiles"
SUPERVISOR_DIR="/etc/supervisor/conf.d"
DANTED_CONFIG_DIR="/etc/danted-warp"

# Find config file relative to this script's location, or in install dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../warp_manager.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  # Try install dir
  if [ -n "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/warp_manager.conf" ]; then
    CONFIG_FILE="$INSTALL_DIR/warp_manager.conf"
  elif [ -f "/opt/warp-manager/warp_manager.conf" ]; then
    CONFIG_FILE="/opt/warp-manager/warp_manager.conf"
  elif [ -f "$HOME/warp-manager/warp_manager.conf" ]; then
    CONFIG_FILE="$HOME/warp-manager/warp_manager.conf"
  fi
fi
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# Use BASE_PORT from config if set, otherwise prompt
if [ -z "$BASE_PORT" ]; then
  read -p "Enter starting port for SOCKS proxies [default: 1080]: " BASE_PORT
  BASE_PORT=${BASE_PORT:-1080}
fi

if [ ! -d "$WARP_DIR" ]; then
  echo -e "\033[1;31mwarp-profiles directory not found: $WARP_DIR\033[0m"
  exit 1
fi

COUNT=$(find "$WARP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'warp*' | wc -l)

for i in $(seq 1 $COUNT); do
  NS="warpns$i"
  PORT=$((BASE_PORT + i - 1))
  DANTED_CONF="$DANTED_CONFIG_DIR/$NS.conf"
  SUP_CONF="$SUPERVISOR_DIR/$NS.conf"

  # Create wrapper scripts for the services in the same install directory
  SCRIPTS_DIR="$INSTALL_DIR/scripts"
  mkdir -p "$SCRIPTS_DIR"
  
  # Create danted wrapper script
  DANTED_SCRIPT="$SCRIPTS_DIR/${NS}-danted.sh"
  tee "$DANTED_SCRIPT" > /dev/null <<EOSCRIPT
#!/bin/bash
# Kill existing danted process in the namespace if any
ip netns pids $NS | xargs -r -I{} sudo nsenter -t {} -n pkill danted || true
# Start danted in the namespace
ip netns exec $NS danted -f $DANTED_CONF
EOSCRIPT
  chmod +x "$DANTED_SCRIPT"
  
  # Create socat wrapper script
  SOCAT_SCRIPT="$SCRIPTS_DIR/${NS}-socat.sh"
  tee "$SOCAT_SCRIPT" > /dev/null <<EOSCRIPT
#!/bin/bash
# Kill existing socat process if any
sudo pkill -f "socat TCP-LISTEN:$PORT" || true
# Start socat
socat TCP-LISTEN:$PORT,fork,reuseaddr TCP:10.10.${i}.2:$PORT
EOSCRIPT
  chmod +x "$SOCAT_SCRIPT"
  
  # Create supervisor config file
  tee "$SUP_CONF" > /dev/null <<EOF
[program:$NS-danted]
command=/bin/bash $DANTED_SCRIPT
user=root
autostart=true
autorestart=false
startsecs=3
stderr_logfile=/var/log/$NS-danted.err.log
stdout_logfile=/var/log/$NS-danted.out.log

[program:$NS-socat]
command=/bin/bash $SOCAT_SCRIPT
user=root
autostart=true
autorestart=false
startsecs=3
stderr_logfile=/var/log/$NS-socat.err.log
stdout_logfile=/var/log/$NS-socat.out.log
EOF

done

echo -e "\033[1;33mSupervisor profiles created for $COUNT proxies in $SUPERVISOR_DIR.\033[0m"
echo -e "\033[1;33mReloading supervisor configs...\033[0m"
supervisorctl reread
supervisorctl update
supervisorctl restart all    

echo -e "\033[1;33mDone. Use 'sudo supervisorctl status' to check status.\033[0m"
