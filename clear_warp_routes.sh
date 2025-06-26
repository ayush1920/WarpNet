#!/bin/bash
# clear_warp_routes.sh — delete warpns namespaces, veths & NAT rule

# 1. Delete all warpns<N> namespaces
for ns in $(ip netns list | awk '/^warpns/ {print $1}'); do
  echo "Deleting namespace $ns"
  sudo ip netns delete "$ns"
done

# 2. Remove any leftover veth host‑side interfaces (veth<*>h)
for v in $(ip link show | grep -oE 'veth[0-9]+h'); do
  echo "Deleting link $v"
  sudo ip link delete "$v" 2>/dev/null || echo "Link $v not found"
done

# 3. Flush only the NAT POSTROUTING chain to remove masquerade rules
sudo nft flush chain ip nat POSTROUTING 2>/dev/null && echo "Flushed NAT POSTROUTING chain" || echo "No NAT POSTROUTING chain to flush"

echo "Cleanup complete. Profiles still in ~/warp-profiles."
