#!/bin/bash
# On-phone: ensure adbd listening on tcp 5555, then report listening ports.
adb kill-server >/dev/null 2>&1
adb tcpip 5555 2>&1 | head -2
sleep 1
# Show ports adbd/bound on
cat /proc/net/tcp /proc/net/tcp6 2>/dev/null | awk 'NR>1{print $2}' \
  | grep -v ':0000' | cut -d: -f2 \
  | while read h; do printf "%s\n" $((16#$h)); done | sort -un
