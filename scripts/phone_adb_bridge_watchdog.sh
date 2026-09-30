#!/bin/bash
# Durable adb-to-phone watchdog (independent of wifi / wireless-adb toggle).
# The durable door is the phone's SSH reverse tunnel: Termux sshd dials OUT to
# VPS2:22070 using mobile data (no wifi needed, survives reboot & mesh-down).
# This watchdog ensures an adb bridge (VPS2:5556 -> ssh door -> phone adbd:5555)
# is always up whenever the ssh door answers.
#
# Delivery discipline (audit 23-Sep-2026): this job lands in the Notifications
# room, and log forensics showed 24 messages in 48h - one per successful
# self-heal while the phone door flapped. Self-healing is HEALTHY, so:
#   - restore succeeded  -> SILENT (it fixed itself, no action for Utkarsh)
#   - restore FAILED     -> always print (real problem)
#   - 4+ restores in 6h  -> ONE instability line per 6h window, then quiet
# Old behaviour printed every successful restore.

SSHKEY=/opt/data/home/.ssh/phone_ed25519
PHONE=u0_a363@162.35.173.192
ADB=/opt/data/tools/platform-tools/adb
export HOME=/opt/data/tools/platform-tools
LOG=/tmp/adb_bridge_ssh.log
STATE_DIR=/opt/data/.hermes/state
RESTORES=$STATE_DIR/adb_bridge_restores.txt   # one epoch per successful restore
FLAPMARK=$STATE_DIR/adb_bridge_flap_reported
WINDOW=$((6 * 3600))
FLAP_AT=4

# Prune restores older than the window; clear the flap marker once the window
# is empty so the next instability episode can speak again.
prune_restores() {
    [ -f "$RESTORES" ] || { rm -f "$FLAPMARK"; return; }
    local now win tmp
    now=$(date +%s); win=$((now - WINDOW)); tmp="$RESTORES.tmp"
    awk -v w="$win" '$1 >= w' "$RESTORES" > "$tmp" 2>/dev/null && mv "$tmp" "$RESTORES"
    [ -s "$RESTORES" ] || rm -f "$FLAPMARK"
}

# Called after a SUCCESSFUL restore: silent, except one line when the door is
# clearly flapping (FLAP_AT restores inside the window).
record_restore() {
    prune_restores
    echo "$(date +%s)" >> "$RESTORES"
    local n
    n=$(wc -l < "$RESTORES" 2>/dev/null | tr -d ' ')
    if [ "${n:-0}" -ge "$FLAP_AT" ] && [ ! -f "$FLAPMARK" ]; then
        touch "$FLAPMARK"
        echo "phone adb bridge restored ${n}x in the last 6h - phone door unstable (mobile data flaps). Bridge is up; further restores silent for this window."
    fi
    return 0
}

prune_restores

# 1) Is the ssh reverse door up? If not, nothing to do (stay silent).
if ! timeout 6 ssh -i "$SSHKEY" -o StrictHostKeyChecking=no -o ConnectTimeout=6 \
     -o BatchMode=yes -p 22070 "$PHONE" 'exit 0' >/dev/null 2>&1; then
    exit 0
fi

# 2) Is the adb bridge already up on 5556? Then healthy, stay silent.
if timeout 3 bash -c "cat </dev/null >/dev/tcp/127.0.0.1/5556" 2>/dev/null; then
    exit 0
fi

# 3) Door up but bridge down -> restore the bridge.
pkill -f '5556:localhost:5555' 2>/dev/null
sleep 1
ssh -i "$SSHKEY" -o StrictHostKeyChecking=no -o ConnectTimeout=6 -o BatchMode=yes \
    -p 22070 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes -N -L 5556:localhost:5555 "$PHONE" \
    >"$LOG" 2>&1 &
echo "$(date '+%F %T'): adb bridge restored (ssh door alive, 5556 dropped)" >> /opt/data/gateway-starts.log

# Verify: failure always speaks; success goes through the throttled recorder.
sleep 3
if timeout 4 bash -c "cat </dev/null >/dev/tcp/127.0.0.1/5556" 2>/dev/null; then
    record_restore
else
    echo "adb bridge FAILED to restore - check /tmp/adb_bridge_ssh.log"
fi
exit 0
