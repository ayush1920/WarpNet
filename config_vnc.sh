#!/bin/bash
# Initialization script for multi-VPN service with WireGuard on VNC

set -e

# Error handling: trap errors and print a message
trap 'echo "[ERROR] Script failed at line $LINENO. Exiting." >&2' ERR

# Install required packages
apt install -y wireguard-tools iproute2 curl dante-server socat lsof iptables

# Download and install wgcf if not already present
echo "Checking for wgcf..."
if ! command -v wgcf >/dev/null 2>&1; then
  echo "wgcf not found. Downloading and installing wgcf..."
  wget -qO wgcf https://github.com/ViRb3/wgcf/releases/download/v2.2.26/wgcf_2.2.26_linux_amd64
  chmod +x wgcf && mv wgcf /usr/local/bin/
else
  echo "wgcf is already installed. Skipping download."
fi

# Enable IP forwarding (runtime and persistent)
echo "Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv6.conf.all.forwarding=1
if ! grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf; then
  echo 'net.ipv4.ip_forward=1' | tee -a /etc/sysctl.conf
fi
if ! grep -q '^net.ipv6.conf.all.forwarding=1' /etc/sysctl.conf; then
  echo 'net.ipv6.conf.all.forwarding=1' | tee -a /etc/sysctl.conf
fi

# Prompt user for number of WARP profiles to create, but limit to 64
read -p "Enter number of profiles to create [default: 16, max: 64]: " PROFILE_COUNT
PROFILE_COUNT=${PROFILE_COUNT:-16}
if [ "$PROFILE_COUNT" -gt 64 ]; then
  echo "Limiting number of profiles to 64."
  PROFILE_COUNT=64
fi
echo -e "\033[1;33mNumber of profiles to create: $PROFILE_COUNT\033[0m"

# Use BASE_PORT from config if set, otherwise prompt
if [ -z "$BASE_PORT" ]; then
  read -p "Enter starting port for SOCKS proxies [default: 1080]: " BASE_PORT
  BASE_PORT=${BASE_PORT:-1080}
fi
echo -e "\033[1;33mSOCKS proxies will start from port $BASE_PORT.\033[0m"

# Write the selected base port and profile count to a config file for all scripts to use
SCRIPT_PATH="$(realpath -s "$0")"
INSTALL_DIR="$(dirname "$SCRIPT_PATH")"
CONFIG_FILE="$INSTALL_DIR/warp_manager.conf"
echo "BASE_PORT=$BASE_PORT" > "$CONFIG_FILE"
echo "PROFILE_COUNT=$PROFILE_COUNT" >> "$CONFIG_FILE"
echo "Configuration file created at $CONFIG_FILE."

# Create directory for WARP profiles in install dir
WARP_DIR="$INSTALL_DIR/warp-profiles"
echo "Creating $WARP_DIR directory for WARP profiles..."
mkdir -p "$WARP_DIR"
cd "$WARP_DIR"
echo -e "\033[1;33mWARP profiles will be created in: $WARP_DIR\033[0m"

# Ensure INSTALL_DIR is never / (root)
if [ "$INSTALL_DIR" = "/" ]; then
  echo "[ERROR] Refusing to create warp-profiles in root directory. Exiting." >&2
  exit 1
fi


# Enable kernel forwarding and disable rp_filter
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.conf.all.rp_filter=0 net.ipv4.conf.default.rp_filter=0


# Detect main network interface (default route)
MAIN_IFACE=$(ip route | awk '/default/ {print $5; exit}')
if [ -z "$MAIN_IFACE" ]; then
  echo -e "\033[1;31m[ERROR] Could not detect main network interface. Exiting.\033[0m" >&2
  exit 1
fi

echo -e "\033[1;33mDetected main network interface: $MAIN_IFACE\033[0m"

# Clean up old iptables rules for this script (avoid duplicates)
if command -v iptables >/dev/null 2>&1; then
  echo -e "\033[1;33mCleaning up old iptables rules for Dante ports...\033[0m"
  for i in $(seq 1 $PROFILE_COUNT); do
    CUR_PORT=$((BASE_PORT + i - 1))
    DANTE_IP="10.10.$i.2"
    VETH_HOST="veth${i}h"
    iptables -D INPUT -i "$MAIN_IFACE" -p tcp --dport $CUR_PORT -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i $VETH_HOST -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o $VETH_HOST -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -p tcp -d $DANTE_IP --dport $CUR_PORT -j ACCEPT 2>/dev/null || true
    iptables -t nat -D OUTPUT -p tcp -d 127.0.0.1 --dport $CUR_PORT -j DNAT --to-destination $DANTE_IP:$CUR_PORT 2>/dev/null || true
  done
fi

# Clean up old nftables rules (optional, only if nft is present)
if command -v nft >/dev/null 2>&1; then
  echo "Cleaning up old nftables rules..."
  nft flush ruleset
fi

# Set up iptables FORWARD and DNAT rules for each namespace/profile
if command -v iptables >/dev/null 2>&1; then
  echo -e "\033[1;33mSetting up iptables FORWARD and DNAT rules for each namespace/profile...\033[0m"
  for i in $(seq 1 $PROFILE_COUNT); do
    VETH_HOST="veth${i}h"
    DANTE_IP="10.10.$i.2"
    CUR_PORT=$((BASE_PORT + i - 1))
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
  echo -e "\033[1;33mSetting up nftables rules for NAT and forwarding...\033[0m"
  nft add table ip filter || true
  nft 'add chain ip filter FORWARD { type filter hook forward priority 0; policy accept; }' || true
  nft add table ip nat || true
  nft 'add chain ip nat POSTROUTING { type nat hook postrouting priority 100; policy accept; }' || true
  nft add rule ip nat POSTROUTING ip saddr 10.10.0.0/16 oifname "$MAIN_IFACE" masquerade || true
else
  echo "[WARNING] nftables not found, skipping nftables rules."
fi

# Print summary of port-to-namespace mapping
echo -e "\033[1;33m\nPort-to-Namespace Mapping Summary:\033[0m"
for i in $(seq 1 $PROFILE_COUNT); do
  CUR_PORT=$((BASE_PORT + i - 1))
  NS_NAME="warpns$i"
  DANTE_IP="10.10.$i.2"
  echo "  Host Port $CUR_PORT -> $NS_NAME ($DANTE_IP:$CUR_PORT)"
done

echo -e "\033[1;33mAll namespaces and WARP tunnels are up.\033[0m"



# Disable error trap and set +e for profile creation loop
trap - ERR
set +e
SUCCESS_COUNT=0
while [ $SUCCESS_COUNT -lt $PROFILE_COUNT ]; do
  ATTEMPT=1
  DIR_NAME="warp$((SUCCESS_COUNT+1))"
  echo "Creating profile $DIR_NAME (attempt $ATTEMPT) in $WARP_DIR/$DIR_NAME..."
  mkdir -p "$DIR_NAME"
  cd "$DIR_NAME"
  # Skip generation if profile already exists
  if [ -f wgcf-profile.conf ]; then
    echo "wgcf-profile.conf already exists in $DIR_NAME. Skipping generation."
    SUCCESS_COUNT=$((SUCCESS_COUNT+1))
    cd "$WARP_DIR"
    continue
  fi
  # Retry loop for profile creation
  while true; do
    wgcf register --accept-tos > register.log 2>&1
    wgcf generate > generate.log 2>&1
    # Check if wgcf-profile.conf exists and private key is 44 chars
    if [ -f wgcf-profile.conf ]; then
      PRIV_KEY=$(grep PrivateKey wgcf-profile.conf | head -n1 | awk '{print $3}')
      if [ ${#PRIV_KEY} -eq 44 ]; then
        echo "Profile $DIR_NAME created successfully in $WARP_DIR/$DIR_NAME."
        SUCCESS_COUNT=$((SUCCESS_COUNT+1))
        cd "$WARP_DIR"
        sleep 5
        break
      else
        echo "Private key length invalid (${#PRIV_KEY}). Retrying (attempt $ATTEMPT)..."
      fi
    else
      echo "wgcf-profile.conf not found. Retrying (attempt $ATTEMPT)..."
    fi
    # Cleanup and retry if failed
    cd "$WARP_DIR"
    rm -rf "$DIR_NAME"
    mkdir -p "$DIR_NAME"
    cd "$DIR_NAME"
    sleep 10
    ATTEMPT=$((ATTEMPT+1))
  done
  # End of retry loop
  # No set -e or trap re-enable here

done
# Re-enable error trap and set -e after the loop
trap 'echo "[ERROR] Script failed at line $LINENO. Exiting." >&2' ERR
set -e

# Create netns directory if it doesn't exist
mkdir -p /etc/netns

# Permissions check
if [ "$EUID" -ne 0 ]; then
  echo -e "\033[1;31m[ERROR] Please run this script as root or with sudo.\033[0m" >&2
  exit 1
fi

# --- Create network namespaces, veth pairs, DNS, and WireGuard for all profiles ---
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
  # Assign IPs (delete if already exists)
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

  # Prepare and bring up WireGuard interface
  if [ -f "$CONF_PATH" ]; then
    ip netns exec $NS_NAME wg-quick down "$CONF_PATH" 2>/dev/null || true
    ip netns exec $NS_NAME wg-quick up "$CONF_PATH" || echo "[ERROR] wg-quick up failed for $NS_NAME"
  else
    echo "Config $CONF_PATH not found, skipping $NS_NAME"
  fi

done
# --- End netns setup ---

echo -e "\033[1;33m$SUCCESS_COUNT profiles created successfully in $WARP_DIR.\033[0m"
