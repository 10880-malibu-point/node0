#!/data/data/com.termux/files/usr/bin/sh
# start_stack.sh - launch the whole phone stack fully detached.
# Run via: run-as com.termux sh -c '...'
# Everything is setsid'd from a double-forked script so it outlives the adb
# shell (a plain `setsid ... &` from run-as gets reaped when run-as exits).
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export PATH=$PREFIX/bin:/system/bin

# hold a wakelock
command -v termux-wake-lock >/dev/null 2>&1 && termux-wake-lock >/dev/null 2>&1

# 1. sshd on 8022
if ! pgrep -f "usr/bin/sshd" >/dev/null 2>&1; then
  nohup setsid "$PREFIX/bin/sshd" -E "$HOME/sshd.log" </dev/null >>"$HOME/sshd.log" 2>&1 &
  echo "$(date '+%F %T'): sshd launched" >> "$HOME/start.log"
fi
sleep 3

# 2. supervisor (owns sshd + reverse tunnel + adb pin)
if ! pgrep -f "home/supervisor.sh" >/dev/null 2>&1; then
  nohup setsid "$PREFIX/bin/sh" "$HOME/supervisor.sh" </dev/null >>"$HOME/supervisor.out" 2>&1 &
  echo "$(date '+%F %T'): supervisor launched" >> "$HOME/start.log"
fi
sleep 2

# 3. sensor capture
if [ -x "$HOME/sensor_capture.sh" ] && ! pgrep -f "sensor_capture.sh" >/dev/null 2>&1; then
  nohup setsid "$PREFIX/bin/bash" "$HOME/sensor_capture.sh" </dev/null >>"$HOME/sensor_capture.log" 2>&1 &
  echo "$(date '+%F %T'): sensor_capture launched" >> "$HOME/start.log"
fi

# 4. phone watchdog
if [ -x "$HOME/phone_watchdog.sh" ] && ! pgrep -f "phone_watchdog.sh" >/dev/null 2>&1; then
  nohup setsid "$PREFIX/bin/bash" "$HOME/phone_watchdog.sh" </dev/null >>"$HOME/watchdog.out" 2>&1 &
  echo "$(date '+%F %T'): phone_watchdog launched" >> "$HOME/start.log"
fi

# 5. wake scheduler
if [ -x "$HOME/phone_wake_scheduler.sh" ] && ! pgrep -f "phone_wake_scheduler.sh" >/dev/null 2>&1; then
  nohup setsid "$PREFIX/bin/bash" "$HOME/phone_wake_scheduler.sh" </dev/null >>"$HOME/wake_sched.log" 2>&1 &
  echo "$(date '+%F %T'): wake_scheduler launched" >> "$HOME/start.log"
fi

echo "STACK_LAUNCHED"
