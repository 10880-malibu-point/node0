#!/data/data/com.termux/files/usr/bin/sh
# boot_start.sh - Termux:Boot autostart. Launches the self-healing supervisor
# (supervisor.sh) once at boot. The supervisor then owns sshd + the reverse
# tunnel and keeps both alive forever, restarting on crash OR wedge.
#
# Also starts the sensor capture + wake scheduler + phone watchdog, so the whole
# stack survives a reboot without any manual step.

export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export PATH=$PREFIX/bin:/system/bin

# wait for network + system to be up before starting daemons
sleep 15

# hold a wakelock so Android does not freeze the CPU and kill our daemons
termux-wake-lock >/dev/null 2>&1

# launch the supervisor loop detached (if not already running)
if ! pgrep -f "home/supervisor.sh" >/dev/null 2>&1; then
  setsid sh -c "$HOME/supervisor.sh" >/dev/null 2>&1 &
  echo "$(date '+%F %T'): supervisor launched from boot" >> "$HOME/boot.log" 2>&1
fi

# sensor capture (needs Termux:API)
if [ -x "$HOME/sensor_capture.sh" ] && ! pgrep -f "sensor_capture.sh" >/dev/null 2>&1; then
  setsid sh -c "$HOME/sensor_capture.sh" >/dev/null 2>&1 &
  echo "$(date '+%F %T'): sensor_capture launched from boot" >> "$HOME/boot.log" 2>&1
fi

# phone watchdog (keeps everything alive if Android kills it)
if [ -x "$HOME/phone_watchdog.sh" ] && ! pgrep -f "phone_watchdog.sh" >/dev/null 2>&1; then
  setsid sh -c "$HOME/phone_watchdog.sh" >/dev/null 2>&1 &
  echo "$(date '+%F %T'): phone_watchdog launched from boot" >> "$HOME/boot.log" 2>&1
fi

# wake scheduler (native-independent daily alarm)
if [ -x "$HOME/phone_wake_scheduler.sh" ] && ! pgrep -f "phone_wake_scheduler.sh" >/dev/null 2>&1; then
  setsid sh -c "$HOME/phone_wake_scheduler.sh" >/dev/null 2>&1 &
  echo "$(date '+%F %T'): wake_scheduler launched from boot" >> "$HOME/boot.log" 2>&1
fi
