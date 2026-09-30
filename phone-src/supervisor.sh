#!/data/data/com.termux/files/usr/bin/bash
# supervisor.sh v7 - phone-side supervisor: keeps the WHOLE stack alive forever.
# Launched at boot by Termux:Boot, and by phone_bringup.sh.
#
# v7 (18-Sep-2026) - FIXES THE BUG THAT MADE v5/v6 USELESS:
#   v5 and v6 ran under `#!/data/.../sh`, which on Termux is DASH. Dash has no
#   /dev/tcp redirection, so EVERY health probe failed with
#   "can't create /dev/tcp/127.0.0.1/8022: No such file or directory".
#   Result: the loop believed sshd was permanently down and the roundtrip was
#   permanently broken, so it restarted things forever and never converged -
#   while the tunnel silently stayed dead. All probes now run under bash.
#   Also: a dead Termux APP process takes sshd+tunnel+supervisor with it, so the
#   stack must be revivable from outside (host cron) as well as at boot.
#
# Env overrides (optional):
#   PSSH_HOST (162.35.173.192) PSSH_TUNNEL_DOOR (22070) PSSH_ADB_DOOR (5556)
#   PSSH_LOCAL_SSHD (8022) PSSH_LOCAL_ADBD (5555) PSSH_HOST_USER (root)
#   PSSH_REV_KEY ($HOME/.ssh/id_phone_reverse)

export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export PATH=$PREFIX/bin:/system/bin
export LOG=$HOME/supervisor.log

BASH=$PREFIX/bin/bash
HOST="${PSSH_HOST:-162.35.173.192}"
TUNNEL_DOOR="${PSSH_TUNNEL_DOOR:-22070}"
ADB_DOOR="${PSSH_ADB_DOOR:-5556}"
LOCAL_SSHD="${PSSH_LOCAL_SSHD:-8022}"
LOCAL_ADBD="${PSSH_LOCAL_ADBD:-5555}"
HOST_USER="${PSSH_HOST_USER:-root}"
REV_KEY="${PSSH_REV_KEY:-$HOME/.ssh/id_phone_reverse}"
MY_USER="$(whoami 2>/dev/null || echo u0_a363)"
PADB=$PREFIX/bin/adb

log(){ echo "$(date '+%F %T'): $*" >> "$LOG"; }
log "supervisor v7 (bash probes) started pid=$$ as=$MY_USER"

# Port-open probe that works on Termux: use bash's /dev/tcp (dash cannot).
port_open(){
  timeout 5 "$BASH" -c "exec 3<>/dev/tcp/127.0.0.1/$1" 2>/dev/null
}

# Full roundtrip: phone -> host reverse door -> back into phone sshd 8022.
wedge_probe(){
  timeout 15 "$PREFIX/bin/ssh" -i "$REV_KEY" \
    -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -o ConnectTimeout=8 -o BatchMode=yes \
    "$MY_USER@$HOST" -p "$TUNNEL_DOOR" true >/dev/null 2>&1
}

# nohup+setsid so the child outlives this shell (bare setsid gets reaped).
spawn(){ nohup setsid "$BASH" -c "$1" >/dev/null 2>&1 & }

start_sshd(){ spawn "$PREFIX/bin/sshd -E $HOME/sshd.log 2>&1"; }

start_tunnel(){
  spawn "$PREFIX/bin/ssh -i $REV_KEY \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -o ExitOnForwardFailure=yes -o ConnectTimeout=15 \
    -N -T \
    -R 0.0.0.0:$TUNNEL_DOOR:127.0.0.1:$LOCAL_SSHD \
    -R 0.0.0.0:$ADB_DOOR:127.0.0.1:$LOCAL_ADBD \
    $HOST_USER@$HOST \
    >> $HOME/revtunnel.log 2>&1"
}

# Keep the Android wake lock (foreground service) so ColorOS does not reap us.
keep_wakelock(){
  if command -v termux-wake-lock >/dev/null 2>&1; then
    termux-wake-lock >/dev/null 2>&1
    log "wake lock re-asserted"
  fi
}

ensure(){ # ensure <script> <pgrep-pattern>
  [ -x "$1" ] || return 0
  pgrep -f "$2" >/dev/null 2>&1 || { log "$2 dead - restarting"; spawn "$1"; }
}

adb_pin(){
  $PADB connect 127.0.0.1:$LOCAL_ADBD >/dev/null 2>&1
  $PADB -s 127.0.0.1:$LOCAL_ADBD shell true >/dev/null 2>&1 && return 0
  log "adbd not pinned on $LOCAL_ADBD"
  return 1
}

while true; do
  # 1. sshd listener
  port_open "$LOCAL_SSHD" || { log "sshd $LOCAL_SSHD not listening - starting"; start_sshd; sleep 3; }

  # 2. reverse tunnel (owns both doors)
  TUNNEL_PID="$(pgrep -f id_phone_reverse 2>/dev/null | head -1)"
  if [ -z "$TUNNEL_PID" ]; then
    log "reverse tunnel process dead - restarting tunnel"
    start_tunnel; sleep 8
  elif ! wedge_probe; then
    log "roundtrip FAILED - restarting tunnel"
    kill "$TUNNEL_PID" 2>/dev/null; sleep 2
    start_tunnel; sleep 8
  fi

  # 3. the other three components - owned here so the wake alarm cannot die
  ensure "$HOME/sensor_capture.sh"      "sensor_capture.sh"
  ensure "$HOME/phone_watchdog.sh"      "phone_watchdog.sh"
  ensure "$HOME/phone_wake_scheduler.sh" "phone_wake_scheduler.sh"

  # 4. wake lock + adb pinning
  keep_wakelock
  [ -x "$PADB" ] && adb_pin >>"$LOG" 2>&1 || true

  sleep 60
done
