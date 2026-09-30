#!/data/data/com.termux/files/usr/bin/bash
# phone_watchdog.sh v2 (18-Sep-2026) - phone-side last-resort watchdog.
# Runs every 60s and restarts any dead member of the stack with setsid so the
# restart survives this shell. This is the net for when Android kills a
# background process despite the wakelock.
#
# v2 changes: supervises the SUPERVISOR (not reverse_tunnel.sh, which the
# supervisor replaced), and no longer requires the older script names.
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export PATH=$PREFIX/bin:/system/bin
LOG=$HOME/watchdog.log

log(){ echo "$(date '+%F %T'): $*" >> "$LOG"; }

while true; do
  # 1. the supervisor (owns sshd + reverse tunnel + adb pinning)
  if ! pgrep -f "home/supervisor.sh" >/dev/null 2>&1; then
    log "supervisor dead - restarting"
    setsid sh -c "$HOME/supervisor.sh" >/dev/null 2>&1 &
  fi
  # 2. sensor capture
  if [ -x "$HOME/sensor_capture.sh" ] && ! pgrep -f "sensor_capture.sh" >/dev/null 2>&1; then
    log "sensor_capture dead - restarting"
    setsid sh -c "$HOME/sensor_capture.sh" >/dev/null 2>&1 &
  fi
  # 3. local wake scheduler
  if [ -x "$HOME/phone_wake_scheduler.sh" ] && ! pgrep -f "phone_wake_scheduler.sh" >/dev/null 2>&1; then
    log "wake_scheduler dead - restarting"
    setsid sh -c "$HOME/phone_wake_scheduler.sh" >/dev/null 2>&1 &
  fi
  sleep 60
done
