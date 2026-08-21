# 🐧 Cloud Linux GUI — Full Linux Desktop in Your Browser

Spin up a full Linux graphical desktop — accessible from any browser, anywhere — with a single command.

![Linux](https://img.shields.io/badge/Linux-Desktop-blue?style=for-the-badge)
![Cloudflare](https://img.shields.io/badge/Cloudflare-Tunnel-orange?style=for-the-badge)
![NoVNC](https://img.shields.io/badge/NoVNC-Web--native-cyan?style=for-the-badge)

## ✨ Features

- **🖥️ Full desktop experience** — XFCE desktop inside your browser, no VNC client needed
- **⚡ One-command setup** — install and run in under 2 minutes
- **🔒 No open ports** — Cloudflare Tunnel handles the exposure securely
- **📱 Works on everything** — desktop, tablet, phone, old browsers
- **💪 Real Linux** — full apt/dpkg packages, run GUI apps natively
- **🧩 Lightweight** — works on a $5/month VPS with 1GB RAM

## 🚀 Quick Start

```bash
# One-line install
bash -c "$(curl -fsSL https://raw.githubusercontent.com/unn-known1/cloud-linux-gui/main/install.sh)"

# Or step by step
git clone https://github.com/unn-known1/cloud-linux-gui.git
cd cloud-linux-gui
chmod +x install.sh && ./install.sh
```

The installer starts the desktop, a noVNC web client, and a free quick
Cloudflare Tunnel automatically — it prints your `*.trycloudflare.com` URL
when done (also saved to `/opt/tunnel_url.txt`).

### Options

```bash
sudo bash install.sh [OPTIONS]

    --resolution WxH     Desktop resolution (default: 1366x768)
    --port N             VNC port, 5901-5999 (default: 5901)
    --desktop NAME       Desktop environment: xfce | mate (default: xfce)
    --password PASS      Set a specific VNC password (first 8 chars are used)
    --new-password       Generate a new password even if one exists
    --no-tunnel          Skip the Cloudflare quick tunnel
```

Re-running the installer reuses your existing VNC password unless you pass
`--new-password` or `--password`.

### Managing services

On systemd systems everything runs as `cloud-gui-*` services — auto-start on
boot, restart on failure. On non-systemd environments it falls back to nohup.

```bash
sudo /opt/cloud-linux-gui/status.sh            # live status of every service
sudo /opt/cloud-linux-gui/stop.sh              # stop everything
sudo systemctl start cloud-gui-*               # start again (systemd mode)
sudo systemctl disable --now cloud-gui-*       # disable autostart
```

For a stable custom domain you can optionally run a named tunnel instead of
the quick tunnel:
```bash
cloudflared tunnel create linux-gui
cloudflared tunnel route dns linux-gui gui.yourdomain.com
cloudflared tunnel run linux-gui
```

### Uninstall

```bash
sudo bash uninstall.sh                     # stop services, remove program files
sudo bash uninstall.sh --purge             # also remove VNC passwords & config
sudo bash uninstall.sh --remove-packages   # also apt-purge desktop/VNC packages
```

## 🔒 Security Notes

- The VNC password is the only thing protecting your desktop. RFB
  authentication keys are **8 characters** — servers enforce this limit, so
  longer passwords are silently truncated.
- Quick tunnels (`*.trycloudflare.com`) are **public URLs**. Servers throttle
  repeated failed auth attempts (TigerVNC blacklists hosts after 5 failures),
  but for real protection put **Cloudflare Access** (Zero Trust) in front of a
  named tunnel so only authenticated users reach the VNC endpoint at all.
- The password API on port 6081 binds to localhost only.
- cloudflared is downloaded from a pinned release and verified with SHA256.

## 🏗️ Stack

- **Desktop:** XFCE or MATE on Xvfb, mirrored by x11vnc (TigerVNC fallback)
- **Web access:** noVNC + websockify
- **Tunnel:** Cloudflare Tunnel (cloudflared)
- **Services:** systemd units (nohup fallback)

## 💡 Use Cases

- Run GUI apps on a remote server without SSH X-forwarding
- Access your Linux desktop from a locked-down corporate network
- Browser-only device (Chromebook, iPad) accessing a full Linux machine
- Quick Linux desktop for testing without a VM

## ⭐ If this helped you, star the repo!

MIT License — built with 💻 by [Gaurang Patel](https://github.com/unn-known1)