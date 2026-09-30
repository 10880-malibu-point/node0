#!/bin/bash
# Which phone crons depend on adb (now dead) vs the ssh door (alive)?
echo "=== phone-related cron scripts and their door usage ==="
for f in phone_disable_watchdog.sh phone_sensor_pull.sh phone_state_track.py \
         phone_egress_watchdog.sh phone_adb_bridge_watchdog.sh phone_tunnel_watchdog.sh \
         phone_door_watchdog.sh; do
  p=/opt/data/scripts/$f
  [ -f "$p" ] || p=/opt/data/.hermes/scripts/$f
  [ -f "$p" ] || { echo "$f  -> MISSING"; continue; }
  adb_n=$(grep -c 'adb ' "$p" 2>/dev/null)
  ssh_n=$(grep -cE 'ssh ' "$p" 2>/dev/null)
  printf "%-34s adb_refs=%-3s ssh_refs=%-3s\n" "$f" "$adb_n" "$ssh_n"
done

echo
echo "=== does the ssh door still give a usable shell? ==="
SSH="-i /opt/data/home/.ssh/phone_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes"
timeout 20 ssh $SSH -p 22070 u0_a363@162.35.173.192 'echo SSH_DOOR_OK; id; whoami' 2>&1 | tr -d '\r' | tail -3

echo
echo "=== can the phone Termux reach its own adbd / can adbd be started? ==="
timeout 20 ssh $SSH -p 22070 u0_a363@162.35.173.192 \
  'P=$PREFIX/bin; echo "settings bins: $(command -v settings || echo none)"; echo "svc: $(command -v svc || echo none)"; echo "adb client: $([ -x $P/adb ] && echo yes || echo no)"; $P/adb devices 2>&1 | head -3' 2>&1 | tr -d '\r'

echo
echo "=== adb 5555 poll (does adbd come back on its own?) ==="
for i in 1 2 3 4 5 6; do
  timeout 4 bash -c 'cat </dev/null >/dev/tcp/10.7.0.3/5555' 2>/dev/null && { echo "t+$((i*10))s 5555 OPEN"; break; } || echo "t+$((i*10))s 5555 closed"
  sleep 10
done
