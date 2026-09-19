#!/bin/bash
# Silent watchdog: phone reverse tunnel (VPS2:22070) health
# Silent while UP. Alerts only when DOWN (stateful, re-nags every ~6 ticks).
# State file tracks last alert time to avoid spamming every tick.
STATE=/opt/data/scripts/phone_tunnel.state
PORT=22070
HOST=162.35.173.192

# Check if the tunnel is listening on VPS2
if timeout 5 bash -c "cat </dev/null >/dev/tcp/$HOST/$PORT" 2>/dev/null; then
    # UP - clear state, stay silent
    rm -f "$STATE"
    exit 0
fi

# DOWN - decide whether to alert
NOW=$(date +%s)
LAST=$(cat "$STATE" 2>/dev/null || echo 0)
DIFF=$(( NOW - LAST ))

if [ "$DIFF" -gt 1800 ]; then
    # First alert, or re-nag after 30 min of persistent outage
    echo "PHONE TUNNEL DOWN: reverse tunnel to phone (VPS2:$PORT) is not listening. Phone may be off, Termux killed, or VPN dropped. Check phone."
    echo "$NOW" > "$STATE"
else
    # Recently alerted - stay silent
    exit 0
fi
