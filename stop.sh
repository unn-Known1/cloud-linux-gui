#!/bin/bash
# Safely stop only Cloud Linux GUI processes (does NOT use pkill -f)
# This avoids killing other servers/services on the system

PID_DIR="/tmp/cloud-gui-pids"

if [ ! -d "$PID_DIR" ]; then
    echo "[-] No Cloud Linux GUI PID directory found. Nothing to stop."
    echo "    (Services may have been started by an older version.)"
    echo "    To stop them manually by name (less safe):"
    echo "      pkill -f cloudflared"
    echo "      pkill -f websockify"
    echo "      tigervncserver -kill :1"
    exit 1
fi

echo "[*] Stopping Cloud Linux GUI services..."

STOPPED=0
for pidfile in "$PID_DIR"/*; do
    [ -f "$pidfile" ] || continue
    name=$(basename "$pidfile")
    pid=$(cat "$pidfile" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "  Stopping $name (PID $pid)..."
        kill "$pid" 2>/dev/null && STOPPED=$((STOPPED + 1))
        sleep 1
        kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
    fi
    rm -f "$pidfile"
done

rm -f /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null || true

echo "[+] Stopped $STOPPED process(es)"
echo "[+] PID directory cleaned"
