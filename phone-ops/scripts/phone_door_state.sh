#!/bin/bash
# Post-recovery state check of the phone door stack.
SSH="-i /opt/data/home/.ssh/phone_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
echo "=== stack processes on phone ==="
timeout 25 ssh $SSH -p 22070 u0_a363@162.35.173.192 \
  "ps -ef | grep -v grep | grep -E 'supervisor|usr/bin/sshd|id_phone_reverse' | sed 's/  */ /g' | cut -c1-110" 2>&1 | tr -d '\r'

echo "=== adbd / boot state ==="
timeout 20 ssh $SSH -p 22070 u0_a363@162.35.173.192 \
  'echo tcp.port=$(getprop service.adb.tcp.port); echo usb.config=$(getprop sys.usb.config); echo adbd_count=$(ps -ef | grep -v grep | grep -c adbd); echo boot_completed=$(getprop sys.boot_completed)' 2>&1 | tr -d '\r'

echo "=== VPS2 door holders ==="
timeout 30 ssh -i /opt/data/home/.ssh/id_ed25519 -o StrictHostKeyChecking=no \
  -o ConnectTimeout=10 -o BatchMode=yes root@162.35.173.192 \
  "ss -ltnp 2>/dev/null | grep -E ':22070|:5556'" 2>&1 | tr -d '\r'

echo "=== watchdog log ==="
tail -6 /opt/data/scripts/phone_door_watchdog.log 2>/dev/null || echo "(none)"
