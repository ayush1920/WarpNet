#!/bin/bash

set -e

# Use INSTALL_DIR from environment, error if not set
if [ -z "$INSTALL_DIR" ]; then
  echo "[ERROR] INSTALL_DIR is not set. Please run this script via install_warp_manager.sh."
  exit 1
fi

# Source config from INSTALL_DIR
CONFIG_FILE="$INSTALL_DIR/warp_manager.conf"
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

# Number of WARP namespaces/proxies
COUNT=$(find "$INSTALL_DIR/warp-profiles" -mindepth 1 -maxdepth 1 -type d | wc -l)

# Config directory
CONFIG_DIR="/etc/danted-warp"

# Ensure config directory exists
if [ ! -d "$CONFIG_DIR" ]; then
  echo "Creating config directory: $CONFIG_DIR"
  sudo mkdir -p "$CONFIG_DIR"
  sudo chmod 755 "$CONFIG_DIR"
fi

# Use BASE_PORT from config if set, otherwise prompt
if [ -z "$BASE_PORT" ]; then
  read -p "Enter starting port for SOCKS proxies [default: 1080]: " BASE_PORT
  BASE_PORT=${BASE_PORT:-1080}
fi

for i in $(seq 1 "$COUNT"); do
    NS="warpns$i"
    WG="wgcf-profile"
    PORT=$((BASE_PORT + i - 1))
    CONF="$CONFIG_DIR/$NS.conf"
    LOG="stderr"

    sudo tee "$CONF" > /dev/null <<EOF
logoutput: $LOG
internal: 10.10.$i.2 port = $PORT
external: $WG

socksmethod: none

client pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
}
socks pass {
  from: 0.0.0.0/0 to: 0.0.0.0/0
  protocol: tcp udp
}
EOF

    echo "Generated: $CONF (listening on port $PORT, namespace $NS)"
done
