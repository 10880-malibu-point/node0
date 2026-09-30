#!/data/data/com.termux/files/usr/bin/bash
# Capture battery + sensor data every 60s to ~/sensor_data.log
# Requires Termux:API app. Location only if permission granted.
LOG=~/sensor_data.log
while true; do
  TS=$(date +%Y-%m-%dT%H:%M:%S%z)
  BAT=$(timeout 8 termux-battery-status 2>/dev/null)
  # Accelerometer (works without location permission)
  ACC=$(timeout 8 termux-sensor -s "icm456xx Accelerometer Non-wakeup" -n 1 2>/dev/null)
  # Ambient light (OPLUS Fusion Light Sensor) - first value is lux
  LIGHT=$(timeout 8 termux-sensor -s "OPLUS Fusion Light Sensor" -n 1 2>/dev/null)
  # Location - only if permission granted
  LOC=$(timeout 8 termux-location -p network 2>/dev/null)
  if [ -n "$LOC" ] && ! echo "$LOC" | grep -q "error"; then
    echo "{\"ts\":\"$TS\",\"battery\":$BAT,\"accel\":$ACC,\"light\":$LIGHT,\"location\":$LOC}" >> $LOG
  else
    echo "{\"ts\":\"$TS\",\"battery\":$BAT,\"accel\":$ACC,\"light\":$LIGHT,\"location\":null}" >> $LOG
  fi
  sleep 60
done
