#!/bin/bash
# Functional test of every phone door after the revivial.
SSH="-i /opt/data/home/.ssh/phone_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
export HOME=/opt/data/tools/platform-tools
ADB=/opt/data/tools/platform-tools/adb

echo "=== door A: VPS2:5556 adb over reverse tunnel ==="
timeout 20 $ADB kill-server >/dev/null 2>&1
timeout 20 $ADB start-server >/dev/null 2>&1
timeout 25 $ADB connect 162.35.173.192:5556 2>&1 | tr -d '\r' | tail -2
timeout 20 $ADB -s 162.35.173.192:5556 shell whoami 2>&1 | tr -d '\r' | tail -2

echo "=== door B: mesh adb 10.7.0.3:5555 ==="
timeout 25 $ADB connect 10.7.0.3:5555 2>&1 | tr -d '\r' | tail -2

echo "=== adbd reality on the phone (via ssh door) ==="
timeout 25 ssh $SSH -p 22070 u0_a363@162.35.173.192 \
  'ls /proc/net/tcp >/dev/null 2>&1 && echo "5555 listener (hex 15B3): $(awk "\$2 ~ /:15B3$/ {print \$2}" /proc/net/tcp 2>/dev/null | head -2)"; echo "--- adb-ish procs ---"; ps -ef 2>/dev/null | grep -iE "adbd|adb " | grep -v grep | head -5; echo "--- termux adb binary ---"; ls -l $PREFIX/bin/adb 2>/dev/null || echo "no adb binary in Termux"' 2>&1 | tr -d '\r'
