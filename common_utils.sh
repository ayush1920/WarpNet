#!/bin/bash
# common_utils.sh - Common utility functions for WarpNest scripts

# Function to detect and set INSTALL_DIR
detect_install_dir() {
    if [ -z "$INSTALL_DIR" ]; then
        if [ -f "$CONFIG_FILE" ]; then
            INSTALL_DIR=$(dirname "$CONFIG_FILE")
        elif [ -d "/opt/warp-manager/warp-profiles" ]; then
            INSTALL_DIR="/opt/warp-manager"
        elif [ -d "$HOME/warp-manager/warp-profiles" ]; then
            INSTALL_DIR="$HOME/warp-manager"
        else
            INSTALL_DIR="/opt/warp-manager"
        fi
    fi
    export INSTALL_DIR
}

# Function to detect and set CONFIG_FILE path
detect_config_file() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[1]}")" && pwd)"
    
    # Try relative to script first
    CONFIG_FILE="$script_dir/warp_manager.conf"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        # Try various install directories
        for dir in "$INSTALL_DIR" "/opt/warp-manager" "$HOME/warp-manager" "$script_dir"; do
            if [ -f "$dir/warp_manager.conf" ]; then
                CONFIG_FILE="$dir/warp_manager.conf"
                break
            fi
        done
    fi
    export CONFIG_FILE
}

# Function to load configuration with BASE_PORT fallback
load_config_with_base_port() {
    local default_port=${1:-1080}
    
    # Load config if exists
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    fi
    
    # Prompt for BASE_PORT if not set
    if [ -z "$BASE_PORT" ]; then
        read -p "Enter starting port for SOCKS proxies [default: $default_port]: " BASE_PORT
        BASE_PORT=${BASE_PORT:-$default_port}
    fi
    export BASE_PORT
}

# Function to setup common directories
setup_common_dirs() {
    export WARP_DIR="$INSTALL_DIR/warp-profiles"
    export SUPERVISOR_DIR="/etc/supervisor/conf.d"
    export DANTED_CONFIG_DIR="/etc/danted-warp"
    
    # Ensure critical directories exist
    mkdir -p "$DANTED_CONFIG_DIR" 2>/dev/null || true
}

# Function to reload systemd services safely
reload_systemd_safe() {
    echo -e "\033[1;33mReloading systemd daemon...\033[0m"
    systemctl daemon-reload || {
        echo -e "\033[1;31mWarning: Failed to reload systemd daemon\033[0m"
        return 1
    }
}

# Function to print colored status messages
print_status() {
    local level="$1"
    local message="$2"
    
    case "$level" in
        "info")    echo -e "\033[1;33m$message\033[0m" ;;
        "success") echo -e "\033[1;32m$message\033[0m" ;;
        "error")   echo -e "\033[1;31m$message\033[0m" ;;
        "warning") echo -e "\033[1;33m$message\033[0m" ;;
        *)         echo "$message" ;;
    esac
}

# Function to count WARP profiles
count_warp_profiles() {
    if [ -d "$WARP_DIR" ]; then
        find "$WARP_DIR" -mindepth 1 -maxdepth 1 -type d -name 'warp*' | wc -l
    else
        echo "0"
    fi
}

# Function to get port for profile index
get_proxy_port() {
    local index="$1"
    echo $((BASE_PORT + index - 1))
}

# Function to get namespace name for index
get_namespace_name() {
    local index="$1"
    echo "warpns$index"
}

# Function to get IP for namespace
get_namespace_ip() {
    local index="$1"
    echo "10.10.$index.2"
}

# Initialize common variables when sourced
init_common_vars() {
    detect_install_dir
    detect_config_file
    setup_common_dirs
}
