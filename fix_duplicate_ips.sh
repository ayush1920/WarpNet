#!/bin/bash
# fix_duplicate_ips.sh - Detect and fix duplicate IP addresses in WARP profiles

set -e

# Find config file and installation directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/warp_manager.conf"
if [ ! -f "$CONFIG_FILE" ] && [ -d "/opt/warp-manager" ] && [ -f "/opt/warp-manager/warp_manager.conf" ]; then
  CONFIG_FILE="/opt/warp-manager/warp_manager.conf"
elif [ ! -f "$CONFIG_FILE" ] && [ -f "$HOME/warp-manager/warp_manager.conf" ]; then
  CONFIG_FILE="$HOME/warp-manager/warp_manager.conf"
fi

# Set WARP_DIR to match the install location
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

if [ ! -d "$WARP_DIR" ]; then
  echo -e "\033[1;31mERROR: warp-profiles directory not found: $WARP_DIR\033[0m"
  exit 1
fi

# Load config
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
  echo -e "\033[1;32mLoaded configuration from $CONFIG_FILE\033[0m"
else
  echo -e "\033[1;33mWarning: Could not find configuration file.\033[0m"
fi

# Function to check for duplicate IP addresses in WARP profiles and regenerate if needed
check_and_fix_duplicate_ips() {
  local warp_dir="$1"
  echo -e "\033[1;33mChecking for duplicate IP addresses in WARP profiles...\033[0m"
  
  # Map to store IP addresses and their corresponding profile directories
  declare -A ip_map
  local duplicates_found=false
  
  # First pass: collect all IPs and identify duplicates
  for profile_dir in "$warp_dir"/warp*/; do
    if [ -f "$profile_dir/wgcf-profile.conf" ]; then
      # Extract the IP address from the profile
      local ip=$(grep "Address" "$profile_dir/wgcf-profile.conf" | awk -F= '{print $2}' | tr -d ' ' | cut -d'/' -f1)
      local profile_name=$(basename "$profile_dir")
      
      if [[ -n "$ip" ]]; then
        if [[ -v ip_map["$ip"] ]]; then
          echo -e "\033[1;31mDuplicate IP found: $ip in $profile_name and ${ip_map["$ip"]}\033[0m"
          duplicates_found=true
        else
          ip_map["$ip"]="$profile_name"
          echo -e "\033[1;32m$profile_name: $ip\033[0m"
        fi
      fi
    fi
  done
  
  # Second pass: regenerate profiles with duplicate IPs
  if [ "$duplicates_found" = true ]; then
    echo -e "\033[1;33mRegenerating profiles with duplicate IP addresses...\033[0m"
    
    for profile_dir in "$warp_dir"/warp*/; do
      local profile_name=$(basename "$profile_dir")
      if [ -f "$profile_dir/wgcf-profile.conf" ]; then
        local ip=$(grep "Address" "$profile_dir/wgcf-profile.conf" | awk -F= '{print $2}' | tr -d ' ' | cut -d'/' -f1)
        local count=0
        
        # Skip profiles that are unique
        if [[ $(grep -l "$ip" "$warp_dir"/warp*/wgcf-profile.conf | wc -l) -gt 1 ]]; then
          echo -e "\033[1;33mRegenerating $profile_name with duplicate IP $ip\033[0m"
          
          # Backup the original profile
          cp "$profile_dir/wgcf-profile.conf" "$profile_dir/wgcf-profile.conf.bak"
          mv "$profile_dir/wgcf-account.toml" "$profile_dir/wgcf-account.toml.bak" 2>/dev/null || true
          
          # Move to the profile directory and regenerate
          pushd "$profile_dir" > /dev/null
          # Retry up to 5 times
          while [ $count -lt 5 ]; do
            wgcf register --accept-tos > register.log 2>&1
            wgcf generate > generate.log 2>&1
            
            if [ -f "wgcf-profile.conf" ]; then
              new_ip=$(grep "Address" "wgcf-profile.conf" | awk -F= '{print $2}' | tr -d ' ' | cut -d'/' -f1)
              if [[ -n "$new_ip" && "$new_ip" != "$ip" && ! -v ip_map["$new_ip"] ]]; then
                echo -e "\033[1;32mSuccessfully regenerated $profile_name with new IP $new_ip\033[0m"
                ip_map["$new_ip"]="$profile_name"
                break
              fi
            fi
            
            count=$((count+1))
            echo "Attempt $count failed, retrying..."
            sleep 10
          done
          
          if [ $count -eq 5 ]; then
            echo -e "\033[1;31mFailed to regenerate $profile_name with a unique IP after 5 attempts\033[0m"
            # Restore the backup if we couldn't get a unique IP
            cp "$profile_dir/wgcf-profile.conf.bak" "$profile_dir/wgcf-profile.conf"
            if [ -f "$profile_dir/wgcf-account.toml.bak" ]; then
              cp "$profile_dir/wgcf-account.toml.bak" "$profile_dir/wgcf-account.toml"
            fi
          fi
          
          popd > /dev/null
        fi
      fi
    done
    
    # Final check for duplicates
    unset ip_map
    declare -A ip_map
    duplicates_found=false
    
    echo -e "\033[1;33m\nFinal IP verification:\033[0m"
    for profile_dir in "$warp_dir"/warp*/; do
      if [ -f "$profile_dir/wgcf-profile.conf" ]; then
        local ip=$(grep "Address" "$profile_dir/wgcf-profile.conf" | awk -F= '{print $2}' | tr -d ' ' | cut -d'/' -f1)
        local profile_name=$(basename "$profile_dir")
        
        if [[ -n "$ip" ]]; then
          if [[ -v ip_map["$ip"] ]]; then
            echo -e "\033[1;31mWarning: Duplicate IP still exists: $ip in $profile_name and ${ip_map["$ip"]}\033[0m"
            duplicates_found=true
          else
            ip_map["$ip"]="$profile_name"
            echo -e "\033[1;32m$profile_name: $ip\033[0m"
          fi
        fi
      fi
    done
    
    if [ "$duplicates_found" = true ]; then
      echo -e "\033[1;31m\nSome duplicate IPs could not be resolved. Consider running reset_warpnest.sh to completely reset all profiles.\033[0m"
      return 1
    else
      echo -e "\033[1;32m\nAll IP addresses are now unique!\033[0m"
      return 0
    fi
  else
    echo -e "\033[1;32mNo duplicate IP addresses found. All profiles have unique IPs.\033[0m"
    return 0
  fi
}

# Run the check and fix function
check_and_fix_duplicate_ips "$WARP_DIR"

# Ask if user wants to restart services
if [ $? -eq 0 ]; then
  read -p "Do you want to restart the WARP services to apply changes? [Y/n]: " RESTART
  if [[ ! "$RESTART" =~ ^[Nn]$ ]]; then
    echo -e "\033[1;33mRestarting WARP network namespaces...\033[0m"
    
    # Get profile count
    COUNT=$(find "$WARP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'warp*' | wc -l)
    
    # Restart namespaces to apply updated profiles
    for i in $(seq 1 $COUNT); do
      NS="warpns$i"
      CONF_PATH="$WARP_DIR/warp$i/wgcf-profile.conf"
      
      if [ -f "$CONF_PATH" ]; then
        echo -e "\033[1;33mRestarting WireGuard interface in namespace $NS...\033[0m"
        ip netns exec $NS wg-quick down "$CONF_PATH" 2>/dev/null || true
        ip netns exec $NS wg-quick up "$CONF_PATH" || echo "[ERROR] wg-quick up failed for $NS"
      fi
    done
    
    # Restart supervisor services
    if command -v supervisorctl >/dev/null 2>&1; then
      echo -e "\033[1;33mRestarting supervisor services...\033[0m"
      supervisorctl reread
      supervisorctl update
      supervisorctl restart all
    fi
    
    echo -e "\033[1;32mAll services have been restarted with the updated profiles.\033[0m"
  else
    echo -e "\033[1;33mSkipping service restart. Remember to restart services manually to apply changes.\033[0m"
  fi
else
  echo -e "\033[1;31mFix was incomplete. Consider running reset_warpnest.sh for a complete reset.\033[0m"
fi

echo -e "\033[1;32mDone.\033[0m"
