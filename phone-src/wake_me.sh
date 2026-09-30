#!/data/data/com.termux/files/usr/bin/bash
# wake_me.sh - Loud, multi-channel wake-up for Utkarsh.
# Usage: bash ~/wake_me.sh [minutes_of_alarm]
# Defaults to 3 minutes of alarm. Uses TTS + vibration + loud audio.
# Requires Termux:API app (com.termux.api) installed.

MIN=${1:-3}
ALARM=~/alarm.wav

# 1. Wake the screen (turn display on so it's visible)
termux-wake-lock
# Try to wake the screen via keyevent (needs adb shell perms; best-effort)
if command -v termux-open-url >/dev/null 2>&1; then
  termux-open-url "https://example.com" >/dev/null 2>&1 &
fi

# 2. Spoken wake-up (TTS) - repeat a few times
for i in 1 2 3; do
  termux-tts-speak "Utkarsh, wake up. It is morning. Time to get up." >/dev/null 2>&1
  sleep 1
done

# 3. Loud alarm audio loop for MIN minutes
END=$(( $(date +%s) + MIN*60 ))
while [ $(date +%s) -lt $END ]; do
  # Play the alarm tone (loop it)
  termux-media-player play "$ALARM" >/dev/null 2>&1
  # Vibrate in a pattern
  termux-vibrate -d 1000 -f 500 >/dev/null 2>&1
  sleep 2
  termux-vibrate -d 1000 -f 500 >/dev/null 2>&1
  sleep 2
  # Check if user has silenced (screen on + unlocked) - best effort
  # Just keep going for the full duration
  sleep 5
done

# 4. Final nudge
termux-tts-speak "Wake up Utkarsh. Your alarm is done." >/dev/null 2>&1
termux-vibrate -d 2000 >/dev/null 2>&1
termux-wake-unlock 2>/dev/null
echo "WAKE_DONE $(date +%Y-%m-%dT%H:%M:%S%z)"
