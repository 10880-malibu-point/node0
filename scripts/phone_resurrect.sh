#!/usr/bin/env bash
# phone_resurrect.sh - VPS2-side watchdog that revives the phone stack when the
# Termux APP PROCESS itself has been killed by ColorOS.
#
# WHY THIS EXISTS (18-Sep-2026):
#   Everything resilient on the phone (sshd 8022, the reverse tunnel, supervisor)
#   runs INSIDE the Termux app process. When ColorOS kills that process, there is
#   nothing left inside the phone to restart it - Termux:Boot only fires on a real
#   reboot, not on a process reap. The phone therefore goes dark for hours with no
#   in-band recovery. This script supplies the OUT-OF-BAND path.
#
# Path: VPS2 --(wg mesh)--> sys0 (10.7.0.2) --(LAN)--> phone adb 192.168.31.106:5555
#   adbd is a SYSTEM service, so it keeps running even when the Termux app is dead.
#   Over that door we start Termux (am start) and run phone_bringup.sh as termux.
#
# Also handles: doors closed -> re-run bringup over the LAN adb door.
#
# Usage: phone_resurrect.sh [--dry-run] [--force]
# Host cron: */5 * * * *
set -uo pipefail

DRY=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
  esac
done

SYS0="hermes@10.7.0.2"
SYS0_KEY="/root/.ssh/sys0_ed25519"
PHONE_IP="192.168.31.106"      # fallback only - discovered at runtime (DHCP moves it)
PHONE_ADB="5555"
DOOR_SSH="22070"
DOOR_ADB="5556"
VPS2="127.0.0.1"
LOG="/var/log/phone_resurrect.log"
STATE="/var/lib/phone_resurrect.last"

log(){ echo "$(date -u '+%F %T UTC'): $*" | tee -a "$LOG"; }
[ -w "$(dirname "$LOG")" ] || LOG="/tmp/phone_resurrect.log"

# --- 1. is the reverse ssh door into the phone alive? -------------------------
door_open(){
  timeout 5 bash -c "exec 3<>/dev/tcp/$VPS2/$DOOR_SSH" 2>/dev/null || return 1
  local banner
  banner=$(timeout 5 bash -c "exec 3<>/dev/tcp/$VPS2/$DOOR_SSH; head -n 1 <&3" 2>/dev/null)
  case "$banner" in SSH-2.0-OpenSSH_*) return 0 ;; *) return 1 ;; esac
}

# --- 2. discover the phone on the LAN, then reach its system adbd via sys0 ----
# The phone's DHCP lease moves (was .167, now .106), so never trust a fixed IP.
discover_ip(){
  timeout 120 ssh -i "$SYS0_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
    -o ConnectTimeout=15 "$SYS0" "bash -s" <<'EOS' 2>/dev/null
export HOME=/home/hermes
# Fast path: an existing adb entry in 'device' state
for d in $(adb devices 2>/dev/null | awk '$2=="device"{print $1}'); do
  echo "$d" | grep -q ':' && { echo "${d%%:*}"; exit 0; }
done
# Fallback: scan the /24 for the adb port, then confirm the model
for i in $(seq 1 254); do
  timeout 0.4 bash -c "exec 3<>/dev/tcp/192.168.31.$i/5555" 2>/dev/null && {
    IP=192.168.31.$i
    adb connect "$IP:5555" >/dev/null 2>&1; sleep 1
    M=$(adb -s "$IP:5555" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    [ "$M" = "CPH2619" ] && { echo "$IP"; exit 0; }
  }
done
exit 1
EOS
}

phone_adb(){ # phone_adb "<adb subcommand>"
  local ip="$1"; shift
  timeout 120 ssh -i "$SYS0_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
    -o ConnectTimeout=15 "$SYS0" "bash -s" <<EOS
export HOME=/home/hermes
adb connect $ip:$PHONE_ADB >/dev/null 2>&1
sleep 2
adb -s $ip:$PHONE_ADB $* 2>&1
EOS
}

termux_alive(){
  local out
  out=$(phone_adb "$CUR_IP" "shell pidof com.termux")
  [ -n "${out//[[:space:]]/}" ]
}

revive_stack(){
  log "reviving stack over LAN adb door at $CUR_IP"
  # start the app process (this is what Termux:Boot cannot do)
  phone_adb "$CUR_IP" "shell am start -n com.termux/.app.TermuxActivity" >/dev/null 2>&1
  sleep 5
  # run the idempotent bringup as termux
  phone_adb "$CUR_IP" "shell run-as com.termux /data/data/com.termux/files/usr/bin/bash files/home/phone_bringup.sh" | tail -3
  sleep 20
}

main(){
  if door_open; then
    log "OK - reverse door $DOOR_SSH answers SSH banner"
    echo OK > "$STATE" 2>/dev/null
    exit 0
  fi

  log "DOOR DOWN ($DOOR_SSH) - checking why"
  if [ "$DRY" = 1 ]; then log "dry-run: would probe Termux + revive"; exit 0; fi

  CUR_IP="$(discover_ip)"
  if [ -z "${CUR_IP:-}" ]; then
    log "phone NOT reachable on LAN either (no CPH2619 on 192.168.31.0/24) - cannot revive"
    echo DOWN > "$STATE" 2>/dev/null
    exit 1
  fi
  log "phone found on LAN at $CUR_IP"

  # door down + termux dead  => the classic ColorOS reap
  if termux_alive; then
    log "Termux app ALIVE but door down -> tunnel problem inside phone; running bringup"
  else
    log "Termux app process is DEAD (ColorOS reap) -> restarting app + stack"
  fi
  revive_stack

  if door_open; then
    log "RECOVERED - door $DOOR_SSH is back"
    echo OK > "$STATE" 2>/dev/null
  else
    log "STILL DOWN after revive attempt"
    echo DOWN > "$STATE" 2>/dev/null
  fi
}

main
