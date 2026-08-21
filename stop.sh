#!/bin/bash
# Safely stop only Cloud Linux GUI processes
# - systemd mode: stops the cloud-gui-* units (does NOT disable them)
# - nohup mode:   kills tracked PIDs from /tmp/cloud-gui-pids (no pkill -f)

PID_DIR="/tmp/cloud-gui-pids"

USE_SYSTEMD=false
if command -v systemctl >/dev/null 2>&1 && \
   systemctl list-unit-files "cloud-gui-*" --no-legend 2>/dev/null | grep -q .; then
    USE_SYSTEMD=true
fi

if [ "$USE_SYSTEMD" = false ] && [ ! -d "$PID_DIR" ]; then
    echo "[-] No systemd units and no Cloud Linux GUI PID directory found."
    echo "    Nothing to stop."
    echo "    (Services may have been started by an older version.)"
    echo "    To stop them manually by name (less safe):"
    echo "      pkill -f cloudflared"
    echo "      pkill -f websockify"
    echo "      tigervncserver -kill :1"
    exit 1
fi

echo "[*] Stopping Cloud Linux GUI services..."

if [ "$USE_SYSTEMD" = true ]; then
    echo "  Stopping systemd units..."
    # Reverse dependency order; tunnel first so the URL stops resolving cleanly
    systemctl stop cloud-gui-tunnel.service \
                   cloud-gui-novnc.service \
                   cloud-gui-vnc.service \
                   cloud-gui-desktop.service \
                   cloud-gui-xvfb.service \
                   cloud-gui-password-api.service 2>/dev/null || true
    echo "  (Units remain enabled - 'sudo systemctl start cloud-gui-*' restarts them,"
    echo "   or use 'systemctl disable --now cloud-gui-*' to disable autostart)"
fi

# Expected cmdline keyword per tracked service - guards against killing a
# recycled PID that now belongs to an unrelated process.
# Note: `dbus-launch --exit-with-session CMD` execs CMD, so the tracked xfce
# PID ends up as xfce4-session/mate-session - match all lifecycle names.
expected_keyword() {
    case "$1" in
        xvfb)            echo "Xvfb" ;;
        xfce)            echo "xfce4-session|mate-session|dbus-launch" ;;
        vnc)             echo "vnc" ;;
        tigervnc)        echo "Xvnc" ;;
        x11vnc)          echo "x11vnc" ;;
        websockify)      echo "websockify" ;;
        password_server) echo "vnc_password_server.py" ;;
        cloudflared)     echo "cloudflared" ;;
        urlwatch)        echo "trycloudflare" ;;
        *)               echo "" ;;
    esac
}

STOPPED=0
SKIPPED=0
for pidfile in "$PID_DIR"/*; do
    [ -f "$pidfile" ] || continue
    name=$(basename "$pidfile")
    pid=$(cat "$pidfile" 2>/dev/null)

    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        kw=$(expected_keyword "$name")
        if [ -n "$kw" ] && ! tr '\0' ' ' < "/proc/${pid}/cmdline" 2>/dev/null | grep -qE -- "$kw"; then
            echo "  Skipping $name (PID $pid): process identity mismatch (PID likely recycled)"
            SKIPPED=$((SKIPPED + 1))
            rm -f "$pidfile"
            continue
        fi

        echo "  Stopping $name (PID $pid)..."
        # If the tracked PID leads its own process group, kill the whole group
        # so session children (xfce4 etc.) die too; otherwise kill children
        # individually, then the PID itself. Never signal a group we don't lead.
        if [ "$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')" = "$pid" ]; then
            kill -- "-${pid}" 2>/dev/null || true
        else
            pkill -P "$pid" 2>/dev/null || true
        fi
        kill "$pid" 2>/dev/null && STOPPED=$((STOPPED + 1))
        sleep 1
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null
            pkill -9 -P "$pid" 2>/dev/null || true
        fi
    fi
    rm -f "$pidfile"
done

# Clean up display locks/sockets and runtime dir we created
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true
rm -rf /tmp/runtime-root 2>/dev/null || true

echo "[+] Stopped $STOPPED process(es)"
[ "$SKIPPED" -gt 0 ] && echo "[!] Skipped $SKIPPED stale/recycled PID(s)"
echo "[+] PID directory cleaned"
