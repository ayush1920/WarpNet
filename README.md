# WarpNest: Multi-WARP VPN Manager 🚀🛡️

WarpNest is a powerful, user-friendly tool for creating and managing multiple Cloudflare WARP VPN profiles on your Linux machine. Designed for privacy enthusiasts, developers, and power users, WarpNest lets you spin up isolated VPN namespaces, each with its own WARP identity, and manage them through a modern web UI.

---

## ⚡️ Installation Steps

1. **Clone the repository:**
   ```sh
   git clone https://github.com/yourusername/warpnest.git
   cd warpnest/installer
   ```
2. **Run the installer as root (required):**
   ```sh
   chmod +x install.sh
   sudo bash install.sh
   ```
   - **You must run the installer with `sudo` or as root.**
   - The installer will copy all scripts, set permissions, and launch the main setup.
   - You will be guided through the following prompts:
     - 📁 **Install Directory:** Choose where to install WarpNest (default: `/opt/warp-manager` or your home directory).
     - 🔢 **Number of WARP Profiles:** Enter how many VPN profiles to create (default: 16, max: 64).
     - 🔌 **Base Port:** Enter the starting port for SOCKS proxies (default: 1080).
     - 🛠️ **Profile & Supervisor Setup:** Confirm if you want to create WARP profiles and supervisor configs now.
     - ♻️ **Reset Confirmation:** If running the reset script, you will be asked to confirm before deleting all state.
   - The installer will automatically install all required dependencies and set up the web UI as a systemd service.

3. **Access the Web UI:**
   - After setup, open your browser and go to: `http://<your-server-ip>:5010/` 🌐
   - When prompted for the Web UI password, you can press Enter to use the default password: `Admin@789`.

---

## 🔔 What to Expect During Installation
- You **must** run all scripts as root (with `sudo`).
- The installer and all scripts no longer use `sudo` internally; permissions are assumed.
- You will be asked to confirm or change the install directory.
- You will be prompted for the number of WARP profiles and the base port for proxies.
- You may be asked to confirm profile and supervisor setup steps.
- If you run the reset script, you will be asked to confirm before all data is wiped.

---

## ⚠️ Important: Port Access
- **By default, SOCKS proxies are exposed starting from port `1080` (e.g., 1080, 1081, ...).**
- **You must open these ports (starting from 1080) in your firewall/security group to access the proxies externally.**
- The installer and scripts will set up iptables rules for these ports, but you may need to adjust your cloud provider or system firewall as well.

---

## ✨ Features
- **Create Multiple WARP VPNs:** Instantly generate and manage dozens of independent WARP profiles.
- **Network Isolation:** Each profile runs in its own Linux network namespace for maximum privacy and flexibility.
- **Dynamic Port Mapping:** Expose SOCKS proxies on incrementing ports for easy access.
- **Web UI:** Control and monitor your VPNs with a beautiful Flask-based dashboard.
- **Automated Setup:** One-command installer handles dependencies, configuration, and service management.
- **Customizable:** Choose your install location, number of profiles, and more.
- **Full Reset Option:** Easily reset all profiles, iptables, and supervisor configs with a single command.

---

## 🖥️ Requirements
- Linux (Debian/Ubuntu recommended)
- sudo/root access for full functionality
- Python 3.8+

The installer will automatically install all required packages:
- python3, python3-pip, python3-venv
- supervisor, wireguard-tools, iproute2, curl, nftables
- Cloudflare WARP CLI (`wgcf`)

---

## 🔍 How It Works
1. **Setup:** Installs all dependencies and sets up the project in `/opt/warp-manager` or your chosen directory.
2. **Profile Creation:** Uses `wgcf` to register and generate multiple WARP profiles, each in its own namespace.
3. **Port Mapping:** Each namespace exposes a SOCKS proxy on a unique port (e.g., 1080, 1081, ...). **Open these ports in your firewall!**
4. **Web UI:** Manage and monitor your VPNs from a single dashboard.
5. **Service Management:** Runs as a systemd service for reliability.
6. **Reset:** Use the reset option to clear all profiles, iptables, and supervisor configs and start fresh.

---

## 🛠️ Usage
- To create more WARP profiles, rerun `config_vnc.sh` in your install directory.
- To manage supervisor profiles, rerun `init_supervisor_profiles.sh`.
- To restart the web UI: `systemctl restart warp-manager`
- **To reset everything:** Run `bash reset_warpnest.sh` (see below).

---

## ♻️ Resetting WarpNest
A `reset_warpnest.sh` script is included to:
- Remove all WARP profiles and namespaces
- Flush iptables rules set by WarpNest
- Remove supervisor configs
- Recreate everything from scratch

```sh
sudo bash reset_warpnest.sh
```

---

## 🔒 Security & Privacy
- Each VPN profile is isolated in its own namespace.
- No iptables/nftables rules are applied unless the tools are present.
- No system-wide changes unless you approve them during install.

---

## 🆘 Troubleshooting
- If you encounter permission errors, try running the installer with `sudo`.
- If you want to uninstall, simply remove the install directory and systemd service.
- For advanced networking, review and customize the scripts in your install directory.

---

## 🤝 Contributing
Pull requests and issues are welcome! Help make WarpNest the best multi-WARP VPN manager for Linux.

---

## 📄 License
MIT License

---

**WarpNest** — Take control of your privacy, one WARP at a time. 🕶️🌍
