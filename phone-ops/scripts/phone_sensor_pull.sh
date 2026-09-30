#!/bin/bash
# Pull phone sensor data to local store for context.
# The phone log (~/sensor_data.log) is multi-line JSON and grows monotonically,
# so the simplest correct approach is to mirror the WHOLE file each pull.
# Silent on success.
KEY=/opt/data/home/.ssh/phone_ed25519
DEST=/opt/data/phone_sensor_data.log
TMP=/tmp/phone_sensor_pull.tmp

# Try mesh path first, then reverse tunnel
if timeout 20 ssh -i "$KEY" -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
    u0_a612@10.7.0.3 -p 8022 'cat ~/sensor_data.log' > "$TMP" 2>/dev/null; then
    :
elif timeout 20 ssh -i "$KEY" -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new \
    u0_a612@162.35.173.192 -p 22070 'cat ~/sensor_data.log' > "$TMP" 2>/dev/null; then
    :
else
    rm -f "$TMP"
    exit 0  # phone unreachable - stay silent, try next tick
fi

# Mirror the whole log (it grows monotonically; overwrite keeps it exact)
if [ -s "$TMP" ]; then
    cp "$TMP" "$DEST"
fi
rm -f "$TMP"
exit 0
