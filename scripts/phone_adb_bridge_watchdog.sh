#!/bin/bash
# Durable adb-to-phone watchdog (independent of wifi / wireless-adb toggle).
# The durable door is the phone's SSH reverse tunnel: Termux sshd dials OUT to
# VPS2:22070 using mobile data (no wifi needed, survives reboot & mesh-down).
# This watchdog ensures an adb bridge (VPS2:5556 -> ssh door -> phone adbd:5555)
# is always up whenever the ssh door answers.
# Silent while healthy; restarts the adb bridge only when it has dropped.

SSHKEY=/opt/data/home/.ssh/phone_ed25519
PHONE=u0_a363@162.35.173.192
ADB=/opt/data/tools/platform-tools/adb
export HOME=/opt/data/tools/platform-tools
LOG=/tmp/adb_bridge_ssh.log

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

# Verify
sleep 3
timeout 4 bash -c "cat </dev/null >/dev/tcp/127.0.0.1/5556" 2>/dev/null \
  && echo "adb bridge UP on 5556" \
  || echo "adb bridge FAILED to restore - check /tmp/adb_bridge_ssh.log"
exit 0
