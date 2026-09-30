#!/bin/bash
# Why is adbd dead, and can wireless debugging be re-enabled from the phone side?
SSH="-i /opt/data/home/.ssh/phone_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
R() { timeout 25 ssh $SSH -p 22070 u0_a363@162.35.173.192 "$1" 2>&1 | tr -d '\r'; }

echo "=== adb-related settings (phone side, best-effort) ==="
R 'for s in global adb_wifi_enabled global adb_enabled global adb_wifi_port secure adb_enabled; do printf "%-28s " "$s"; settings get $s 2>/dev/null || echo "(denied)"; done'

echo
echo "=== can Termux user read adbd status via dumpsys? ==="
R 'dumpsys adb 2>&1 | head -8 || echo "(dumpsys denied)"'

echo
echo "=== adbd in logcat (why it died) ==="
R 'logcat -d -t 300 2>/dev/null | grep -iE "adbd|adb_wifi|wireless debug" | tail -12 || echo "(logcat denied)"'

echo
echo "=== supervisor.log tail (what it tried) ==="
R 'tail -12 /data/data/com.termux/files/home/supervisor.log'

echo
echo "=== does the phone Termux adb client see any local adb? ==="
R '$PREFIX/bin/adb connect 127.0.0.1:5555 2>&1 | tail -2; $PREFIX/bin/adb devices 2>&1 | tail -3'
