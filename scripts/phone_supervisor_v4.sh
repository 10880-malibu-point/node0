#!/data/data/com.termux/files/usr/bin/sh
# Phone-side supervisor loop: keeps sshd + reverse tunnel + ADB alive forever.
# Launched once at boot (by boot_start.sh via Termux:Boot), self-heals all three.
# No root needed.
#
# v4 (17-Sep-2026): DROP the pgrep-based sshd check entirely.
#   `pgrep -x sshd` returns rc=1 on this Termux even when the sshd daemon is
#   genuinely running+serving (procps-ng 3.3.17 false-negative). That made the
#   supervisor log "sshd down - restarting" every 60s and spawn a fresh sshd
#   each cycle -> load spike (~3.5) and permanent churn.
#   v4 health = the FUNCTIONAL roundtrip probe (wedge_probe): phone -> host
#   reverse door 22070 -> back into phone sshd 8022. If that roundtrip works,
#   sshd AND tunnel are both up; we do NOTHING. If it fails, restart sshd
#   (idempotent: rebinds or dies harmlessly) then the tunnel.
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export PATH=$PREFIX/bin:/system/bin
export LOG=$HOME/supervisor.log
HOST=162.35.173.192
SSH_TUNNEL_DOOR=22070
ADB_TUNNEL_DOOR=5556
PADB=$PREFIX/bin/adb

log(){ echo "$(date '+%F %T'): $*" >> "$LOG"; }
log "supervisor v4 (functional-probe only) started pid=$$"

# Full roundtrip: phone -> host reverse door -> back into phone sshd 8022.
# ONLY this counts as healthy. No pgrep.
wedge_probe(){
  timeout 15 "$PREFIX/bin/ssh" -i "$HOME/.ssh/probe_ed25519" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 -o BatchMode=yes \
    u0_a363@"$HOST" -p $SSH_TUNNEL_DOOR true >/dev/null 2>&1
}

# start sshd (idempotent) then the reverse tunnel
start_sshd(){ setsid sh -c "$PREFIX/bin/sshd -E $HOME/sshd.log 2>&1" >/dev/null 2>&1 & }

start_tunnel(){
  setsid sh -c "$PREFIX/bin/ssh -i $HOME/.ssh/id_phone_reverse \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes -o ConnectTimeout=15 \
    -N -T \
    -R 0.0.0.0:$SSH_TUNNEL_DOOR:127.0.0.1:8022 \
    -R 0.0.0.0:$ADB_TUNNEL_DOOR:127.0.0.1:5555 \
    root@$HOST \
    > $HOME/revtunnel.log 2>&1" >/dev/null 2>&1 &
}

# Discover the live adbd TCP port on the phone. Order:
#   1. service.adb.tcp.port (set by `adb tcpip N`, survives until adbd restart)
#   2. getprop for wireless-debug runtime
#   3. bounded localhost scan (wireless-debug random ports usually 37k-5xk)
adb_discover(){
  local p cur
  cur=$(getprop service.adb.tcp.port 2>/dev/null)
  [ -n "$cur" ] && [ "$cur" != "0" ] && { echo "$cur"; return 0; }
  cur=$(getprop persist.adb.tcp.port 2>/dev/null)
  [ -n "$cur" ] && [ "$cur" != "0" ] && { echo "$cur"; return 0; }
  for p in $(seq 33000 33500) $(seq 37000 37500) $(seq 42000 42500) \
            $(seq 45000 45500) $(seq 47000 47500) $(seq 49000 49500); do
    if timeout 1 bash -c "exec 3<>/dev/tcp/127.0.0.1/$p" 2>/dev/null; then
      exec 3>&- 3<&- 2>/dev/null
      echo "$p"; return 0
    fi
  done
  return 1
}

adb_pin(){
  local port
  if $PADB connect 127.0.0.1:5555 >/dev/null 2>&1; then
    if $PADB -s 127.0.0.1:5555 shell true >/dev/null 2>&1; then
      log "adb already on 5555"
      return 0
    fi
  fi
  port=$(adb_discover) || { log "adb_discover: no adbd listener (wireless debug off?)"; return 1; }
  if [ "$port" = "5555" ]; then
    log "adbd already on 5555"
    return 0
  fi
  log "adbd on port $port - pinning to 5555"
  $PADB connect "127.0.0.1:$port" >/dev/null 2>&1
  sleep 2
  $PADB -s "127.0.0.1:$port" tcpip 5555 >/dev/null 2>&1
  sleep 3
  $PADB connect 127.0.0.1:5555 >/dev/null 2>&1
}

while true; do
  TUNNEL_PID="$(pgrep -f id_phone_reverse 2>/dev/null | head -1)"

  if [ -z "$TUNNEL_PID" ]; then
    # tunnel process gone: restart sshd (so 8022 listens) then tunnel
    log "reverse tunnel process dead - restarting sshd + tunnel"
    start_sshd
    sleep 2
    start_tunnel
    sleep 8
  elif ! wedge_probe; then
    # roundtrip broken (sshd down OR tunnel wedged): reset both
    log "roundtrip FAILED - restarting sshd + tunnel"
    start_sshd
    sleep 2
    kill "$TUNNEL_PID" 2>/dev/null
    sleep 2
    start_tunnel
    sleep 8
  fi

  # adb: auto-pin to durable 5555 (one-tap wireless-debug recovery)
  adb_pin >>"$LOG" 2>&1 || true

  sleep 60
done
