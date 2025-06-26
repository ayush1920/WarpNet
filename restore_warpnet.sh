#!/bin/bash
# Restore WARP network namespaces, veth pairs, iptables/nftables, and WireGuard after boot

set -e

# Load config
SCRIPT_PATH="$(realpath -s "$0")"
INSTALL_DIR="$(dirname "$SCRIPT_PATH")"
CONFIG_FILE="$INSTALL_DIR/warp_manager.conf"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "[ERROR] Config file $CONFIG_FILE not found. Exiting." >&2
  exit 1
fi
source "$CONFIG_FILE"
WARP_DIR="$INSTALL_DIR/warp-profiles"

# Check required vars
if [ -z "$BASE_PORT" ] || [ -z "$PROFILE_COUNT" ]; then
  echo "[ERROR] BASE_PORT or PROFILE_COUNT not set in config. Exiting." >&2
  exit 1
fi

# Create netns directory if it doesn't exist
mkdir -p /etc/netns

# --- Restore network namespaces, veth pairs, DNS, and WireGuard for all profiles ---
for i in $(seq 1 $PROFILE_COUNT); do
  NS_NAME="warpns$i"
  VETH_HOST="veth${i}h"
  VETH_NS="veth${i}n"
  SUBNET="10.10.$i"
  NS_IP="$SUBNET.2/24"
  HOST_IP="$SUBNET.1/24"
  CONF_PATH="$WARP_DIR/warp$i/wgcf-profile.conf"
  RESOLV_CONF="/etc/netns/$NS_NAME/resolv.conf"

  # Delete namespace if it already exists
  if ip netns list | grep -qw "$NS_NAME"; then
    ip netns del "$NS_NAME"
  fi
  # Delete veth interfaces if they already exist
  ip link del "$VETH_HOST" 2>/dev/null || true
  ip link del "$VETH_NS" 2>/dev/null || true
  # Create namespace
  ip netns add "$NS_NAME"
  # Create veth pair
  ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
  # Move one end to namespace
  ip link set "$VETH_NS" netns "$NS_NAME"
  # Assign IPs
  ip addr flush dev "$VETH_HOST" 2>/dev/null || true
  ip addr add "$HOST_IP" dev "$VETH_HOST"
  ip link set "$VETH_HOST" up
  ip netns exec "$NS_NAME" ip addr flush dev "$VETH_NS" 2>/dev/null || true
  ip netns exec "$NS_NAME" ip addr add "$NS_IP" dev "$VETH_NS"
  ip netns exec "$NS_NAME" ip link set "$VETH_NS" up
  ip netns exec "$NS_NAME" ip link set lo up
  ip netns exec "$NS_NAME" ip route add default via "$SUBNET.1"

  # DNS inside namespace
  mkdir -p /etc/netns/$NS_NAME
  echo -e 'nameserver 1.1.1.1\nnameserver 1.0.0.1' | tee "$RESOLV_CONF" > /dev/null

  # Bring up WireGuard interface
  if [ -f "$CONF_PATH" ]; then
    ip netns exec $NS_NAME wg-quick down "$CONF_PATH" 2>/dev/null || true
    ip netns exec $NS_NAME wg-quick up "$CONF_PATH" || echo "[ERROR] wg-quick up failed for $NS_NAME"
  else
    echo "Config $CONF_PATH not found, skipping $NS_NAME"
  fi

done
# --- End netns setup ---

# Ensure host DNS uses Cloudflare
echo -e 'nameserver 1.1.1.1\nnameserver 1.0.0.1' | tee /etc/resolv.conf > /dev/null

# Enable kernel forwarding and disable rp_filter
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0

# Detect main network interface (default route)
MAIN_IFACE=$(ip route | awk '/default/ {print $5; exit}')
if [ -z "$MAIN_IFACE" ]; then
  echo -e "[ERROR] Could not detect main network interface. Exiting." >&2
  exit 1
fi

echo -e "Restoring iptables rules for Dante ports..."
if command -v iptables >/dev/null 2>&1; then
  for i in $(seq 1 $PROFILE_COUNT); do
    CUR_PORT=$((BASE_PORT + i - 1))
    DANTE_IP="10.10.$i.2"
    VETH_HOST="veth${i}h"
    iptables -A INPUT -i "$MAIN_IFACE" -p tcp --dport $CUR_PORT -j ACCEPT
    iptables -A FORWARD -i $VETH_HOST -j ACCEPT
    iptables -A FORWARD -o $VETH_HOST -j ACCEPT
    iptables -A FORWARD -p tcp -d $DANTE_IP --dport $CUR_PORT -j ACCEPT
    iptables -t nat -A OUTPUT -p tcp -d 127.0.0.1 --dport $CUR_PORT -j DNAT --to-destination $DANTE_IP:$CUR_PORT
  done
else
  echo "[WARNING] iptables not found, skipping iptables rules."
fi

# Set up nftables rules if nft is present
if command -v nft >/dev/null 2>&1; then
  nft add table ip filter || true
  nft 'add chain ip filter FORWARD { type filter hook forward priority 0; policy accept; }' || true
  nft add table ip nat || true
  nft 'add chain ip nat POSTROUTING { type nat hook postrouting priority 100; policy accept; }' || true
  nft add rule ip nat POSTROUTING ip saddr 10.10.0.0/16 oifname "$MAIN_IFACE" masquerade || true
else
  echo "[WARNING] nftables not found, skipping nftables rules."
fi

echo -e "WARP network namespaces and tunnels restored."
