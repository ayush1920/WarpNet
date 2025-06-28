# WarpNest: Multi-WARP VPN Manager 🚀🛡️

WarpNest is your all-in-one toolkit for privacy, automation, and power-user networking. Effortlessly create and manage dozens of independent Cloudflare WARP VPN profiles—each in its own isolated Linux namespace—then control them all from a beautiful web dashboard or your browser.

---

## ⚡️ Quick Start

1. **Clone the repository:**
   ```sh
   git clone https://github.com/yourusername/warpnest.git
   cd warpnest/installer
   ```
2. **Run the installer as root:**
   ```sh
   chmod +x install.sh
   sudo bash install.sh
   ```
   - You'll be guided through setup: choose your install directory, number of VPN profiles, and starting port for proxies.
   - The installer takes care of dependencies, permissions, and systemd service setup.

3. **Access the Web UI:**
   - Open your browser to `http://<your-server-ip>:5010/`
   - Default password: `Admin@789` (change it after first login!)

---

## 🧩 Browser Extensions: Power in Your Browser

### 1. **proxy_extenstion**
- Instantly switch your browser between any active SOCKS proxy with a click.
- See proxy status, auto-refresh the list, and never touch a config file.
- **How to use:**
  - Load the extension in Chrome (Developer Mode > Load unpacked > select `proxy_extenstion` folder).
  - Log in to the WarpNest UI from the popup, pick a proxy, and your browser is routed through that WARP identity.
  - Great for privacy, testing, or region switching on the fly.

### 2. **proxy_overlay_extension**
- Adds a floating overlay to web pages for in-place proxy switching and status.
- Reads from `config.json` and talks to the backend for live updates.
- Perfect for power users who want to manage proxies without leaving their workflow.

---

## 🌐 Web UI Pages: Control at Your Fingertips

### **dante_manager**
- The main dashboard for all your WARP proxies and namespaces.
- **What you can do:**
  - Start, stop, or restart any proxy (or all at once) with a click.
  - See which proxies are running, their ports, namespaces, and public IPs.
  - Batch-generate new proxies for scaling up.
  - Manage your login and password securely.
- Access at: `http://<your-server-ip>:5010/dante_manager`
- Built with Flask, using supervisor for robust process control.

### **chrome_manager**
- Automate launching multiple Chrome browser instances, each with its own SOCKS proxy and WARP identity.
- Download a **ZIP file** containing ready-to-use batch scripts and Chrome user profile folders. Each script launches a Chrome window sandboxed with a different proxy and extension.
- **Practical uses:**
  - Run multiple social media, ad, or research accounts in parallel, each with a unique IP.
  - Test geo-restricted content or automation scripts in separate browser sessions.
  - Keep work, personal, and automation browsing totally separate.
- **How to use:**
  1. Visit `http://<your-server-ip>:5010/chrome_manager`.
  2. Enter the list of URLs you want to open, and assign proxies as needed.
  3. Click **Generate Configuration** and then **Download Batch File** (actually a ZIP archive).
  4. Extract the ZIP on your Windows PC. Inside, you'll find batch files and folders for each Chrome instance.
  5. Run the batch files to launch Chrome windows—each sandboxed, using a different WARP proxy, and preloaded with the overlay extension for proxy info.
- The ZIP file is generated dynamically based on your selections, making it easy to automate multi-profile browsing or testing workflows.

---

## 🔔 What to Expect During Installation
- You **must** run all scripts as root (with `sudo`).
- The installer is interactive and will never make system-wide changes without your approval.
- All scripts assume you have root permissions; no more `sudo` inside scripts.
- You can always reset or uninstall with a single command.

---

## ⚠️ Important: Port Access
- SOCKS proxies start from port `1080` (e.g., 1080, 1081, ...).
- **Open these ports in your firewall or cloud security group** to access proxies from outside.
- The installer sets up iptables rules, but you may need to adjust your cloud or system firewall as well.

---

## ✨ Features & Practical Uses
- **Multiple WARP VPNs:** Instantly spin up dozens of independent VPNs for privacy, scraping, automation, or research.
- **Network Isolation:** Each profile is in its own Linux namespace—no leaks, no cross-talk.
- **Dynamic Port Mapping:** Every proxy gets its own port for easy access and automation.
- **Web UI:** Manage everything from a modern dashboard—no CLI required.
- **Browser Extensions:** Switch proxies in Chrome with a click, or overlay controls on any page.
- **Chrome Manager:** Run multiple Chrome sessions, each with a different IP, for multi-accounting, testing, or automation.
- **Automated Setup:** One-command install, full reset, and easy updates.
- **Customizable:** Choose your install location, number of profiles, and more.
- **Full Reset Option:** Wipe and rebuild everything with `reset_warpnest.sh`.

---

## 🖥️ Requirements
- Linux (Debian/Ubuntu recommended)
- sudo/root access
- Python 3.8+

The installer will automatically install:
- python3, python3-pip, python3-venv
- supervisor, wireguard-tools, iproute2, curl, nftables
- Cloudflare WARP CLI (`wgcf`)

---

## 🔍 How It Works (Behind the Scenes)
1. **Setup:** Installs all dependencies and sets up the project in `/opt/warp-manager` or your chosen directory.
2. **Profile Creation:** Uses `wgcf` to register and generate multiple WARP profiles, each in its own namespace.
3. **Port Mapping:** Each namespace exposes a SOCKS proxy on a unique port (e.g., 1080, 1081, ...).
4. **Web UI:** Manage and monitor your VPNs from a single dashboard.
5. **Service Management:** Runs as a systemd service for reliability.
6. **Reset:** Use the reset option to clear all profiles, iptables, and supervisor configs and start fresh.

---

## 🛠️ Usage
- **Add more WARP profiles:** Rerun `config_vnc.sh` in your install directory.
- **Manage supervisor profiles:** Rerun `init_supervisor_profiles.sh`.
- **Restart the web UI:** `systemctl restart warp-manager`
- **Reset everything:** Run `bash reset_warpnest.sh` (see below).
- **Automate Chrome:** Use the `chrome_manager` page to launch multiple Chrome windows, each with a different proxy.

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
- Each VPN profile is isolated in its own namespace—no accidental leaks.
- No iptables/nftables rules are applied unless the tools are present.
- No system-wide changes unless you approve them during install.
- Password-protected web UI and secure session management.

---

## 🆘 Troubleshooting & Tips
- If you see permission errors, run the installer with `sudo`.
- To uninstall, just remove the install directory and systemd service.
- For advanced networking, review and customize the scripts in your install directory.
- If a proxy isn't working, check the web UI for status, or restart it from the dashboard.
- Use the browser extensions for seamless proxy switching—no manual config needed.

---

## 🤝 Contributing
Pull requests and issues are welcome! Help make WarpNest the best multi-WARP VPN manager for Linux.

---

## 📄 License
MIT License

---

**WarpNest** — Take control of your privacy, automation, and online identity. 🕶️🌍
