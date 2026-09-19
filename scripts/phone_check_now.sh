#!/bin/bash
# Full phone door state check after the user enabled developer options.
echo "=== watchdog log (recent) ==="
tail -4 /opt/data/scripts/phone_door_watchdog.log 2>/dev/null || echo "(none)"

echo
echo "=== supervisor.log tail (is the phone still trying to pin adbd?) ==="
SSH="-i /opt/data/home/.ssh/phone_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
timeout 25 ssh $SSH -p 22070 u0_a363@162.35.173.192 \
  'tail -6 /data/data/com.termux/files/home/supervisor.log' 2>&1 | tr -d '\r' | grep -v Warning

echo
echo "=== adbd listener inside the phone? (5555 = 15B3 hex) ==="
timeout 25 ssh $SSH -p 22070 u0_a363@162.35.173.192 \
  'awk "NR>1 {print \$2}" /proc/net/tcp 2>/dev/null | grep -iE ":15B3$" || echo "no 5555 listener"; echo "usb.config=$(getprop sys.usb.config)"; echo "boot_completed=$(getprop sys.boot_completed)"' 2>&1 | tr -d '\r' | grep -v Warning

echo
echo "=== sweep for a wireless-debugging adbd port on the mesh ==="
found=$(seq 30000 49999 | xargs -P 150 -I{} sh -c 'timeout 1 bash -c "cat </dev/null >/dev/tcp/10.7.0.3/{}" 2>/dev/null && echo {}' 2>/dev/null | tr '\n' ' ')
echo "open high ports: ${found:-none}"

echo
echo "=== door ports ==="
for p in 5555 8022 10809; do timeout 4 bash -c "cat </dev/null >/dev/tcp/10.7.0.3/$p" 2>/dev/null && echo "  10.7.0.3:$p OPEN" || echo "  10.7.0.3:$p closed"; done
for p in 22070 5556; do timeout 4 bash -c "cat </dev/null >/dev/tcp/162.35.173.192/$p" 2>/dev/null && echo "  vps2:$p OPEN" || echo "  vps2:$p closed"; done
