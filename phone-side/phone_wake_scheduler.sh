#!/data/data/com.termux/files/usr/bin/bash
# phone_wake_scheduler.sh - LOCAL fallback wake-up, independent of SSH.
# Fires wake_me.sh at 6:30 AM IST every day IF it hasn't already fired today.
# This is the belt-and-suspenders net: even if Cipher's SSH path to the phone
# is down (mesh + reverse tunnel both dead), the phone still wakes Utkarsh.
# Runs from the phone watchdog loop (every 60s).
#
# Config: WAKE_HOUR / WAKE_MIN (24h IST). Change here to change the time.
WAKE_HOUR=6
WAKE_MIN=30
MARK=~/last_wake_fired

while true; do
  NOW_H=$(date +%H)
  NOW_M=$(date +%M)
  TODAY=$(date +%Y-%m-%d)
  LAST=$(cat "$MARK" 2>/dev/null)

  # Fire at the target minute, once per day
  if [ "$NOW_H" = "$WAKE_HOUR" ] && [ "$NOW_M" = "$WAKE_MIN" ] && [ "$LAST" != "$TODAY" ]; then
    echo "$TODAY" > "$MARK"
    # Fire the alarm in the background (3 min)
    setsid bash ~/wake_me.sh 3 </dev/null >/tmp/wake_me_local.out 2>&1 &
  fi

  sleep 60
done
