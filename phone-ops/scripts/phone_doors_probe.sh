#!/usr/bin/env bash
# phone_doors_probe - authoritative live check of the phone access doors.
#
# Registry fact: phone-reverse-tunnel-doors.
# Durable rule (Sep-2026): the OnePlus phone is reachable on ANY network (wifi or
# mobile data) ONLY through its OWN outbound reverse tunnel to VPS2 - the phone
# dials out, so carrier NAT / no-wifi never blocks us. Two doors ride that tunnel:
#   (1) SSH  : ssh -p 22070 -i /opt/data/home/.ssh/phone_ed25519 u0_a363@162.35.173.192
#   (2) ADB  : adb connect 162.35.173.192:5556  (phone adbd on 5555)
# The tunnel is fired by ~/supervisor.sh on the phone; phone_adb_bridge_watchdog
# re-establishes the adb bridge whenever the ssh door answers.
#
# NOT durable, do NOT rely on: direct adb-over-wifi (adb connect to the phone's
# LAN IP) - Android flips wireless debugging off; needs wifi + LAN reachability.
#
# Run: bash /opt/data/scripts/phone_doors_probe.sh
set -u
HOST=162.35.173.192

echo "== phone doors probe $(date -Is) =="
for p in 22070 5556; do
  if timeout 5 bash -c "cat </dev/null >/dev/tcp/$HOST/$p" 2>/dev/null; then
    echo "door $p: UP"
  else
    echo "door $p: DOWN"
  fi
done
echo "note: the reverse tunnel is phone-initiated; both doors down = phone off,"
echo "      Termux killed, or supervisor.sh not running (the watchdogs cannot"
echo "      heal this - the phone must re-dial)."
