#!/data/data/com.termux/files/usr/bin/bash
# phone_bringup.sh - bring the resilient stack up from a cold Termux (v7, 18-Sep-2026).
# Idempotent. Runs as u0_a363 (via run-as com.termux, Termux itself, or Termux:Boot).
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export PATH=$PREFIX/bin:/system/bin:/system/xbin

HOST=162.35.173.192
TUNNEL_DOOR=22070
ADB_DOOR=5556
LOCAL_SSHD=8022
LOCAL_ADBD=5555
REV_KEY=$HOME/.ssh/id_phone_reverse
LOG=$HOME/resilience.log

log(){ echo "$(date '+%F %T'): $*" >> "$LOG"; }
log "=== bringup start ==="

# --- 0. wake lock: keeps Android from dozing the Termux session out ---
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock 2>/dev/null && log "wake lock acquired" || log "wake lock command failed"
else
  log "termux-wake-lock not found"
fi

# --- 1. clear stale tunnel processes ---
if pkill -f id_phone_reverse 2>/dev/null; then log "killed stale tunnel(s)"; fi

# --- 2. sshd on 8022 ---
if ss -ltn 2>/dev/null | grep -q ":$LOCAL_SSHD"; then
  log "sshd already listening on $LOCAL_SSHD"
else
  sshd -E "$HOME/sshd.log" 2>/dev/null
  sleep 3
  if ss -ltn 2>/dev/null | grep -q ":$LOCAL_SSHD"; then
    log "sshd started on $LOCAL_SSHD"
  else
    log "ERROR: sshd failed to start"
  fi
fi

# --- 3. reverse tunnel owning BOTH doors ---
if pgrep -f id_phone_reverse >/dev/null 2>&1; then
  log "tunnel process already present"
else
  nohup setsid "$PREFIX/bin/ssh" -i "$REV_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes -o ConnectTimeout=15 \
    -N -T \
    -R 0.0.0.0:$TUNNEL_DOOR:127.0.0.1:$LOCAL_SSHD \
    -R 0.0.0.0:$ADB_DOOR:127.0.0.1:$LOCAL_ADBD \
    root@$HOST >> "$HOME/revtunnel.log" 2>&1 &
  log "tunnel spawned pid=$!"
  sleep 8
fi

# --- 4. verify the full roundtrip through the door ---
if timeout 15 "$PREFIX/bin/ssh" -i "$REV_KEY" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 -o BatchMode=yes \
    "u0_a363@$HOST" -p $TUNNEL_DOOR true >/dev/null 2>&1; then
  log "ROUNDTRIP OK via $HOST:$TUNNEL_DOOR"
else
  log "ROUNDTRIP FAILED"
  tail -3 "$HOME/revtunnel.log" 2>/dev/null | while read -r l; do log "  revtunnel: $l"; done
fi

# --- 5. pin adbd to the durable port ---
if [ -x "$PREFIX/bin/adb" ]; then
  "$PREFIX/bin/adb" connect "127.0.0.1:$LOCAL_ADBD" >/dev/null 2>&1
  if "$PREFIX/bin/adb" -s "127.0.0.1:$LOCAL_ADBD" shell true >/dev/null 2>&1; then
    log "adbd pinned on $LOCAL_ADBD"
  else
    log "adbd not yet on $LOCAL_ADBD (supervisor will re-pin)"
  fi
fi

log "=== bringup done ==="
echo "BRINGUP_DONE"
