#!/usr/bin/env bash
# phone_adb_repair.sh - ONE-SHOT: bring durable adb back after phone reboot.
# Prereq (user does once): Developer options -> Wireless debugging -> ON, and
# authorized once (so adb_known_hosts.pb exists on the phone). After that this
# script needs NO further screen-reading: it reads the adbd port off the phone
# itself via the persistent SSH door.
#
# Flow:
#   1. SSH door (VPS2:22070) always dials out from phone -> always reachable.
#   2. Read adbd's listening TCP port FROM the phone (not from the screen).
#   3. Phone-side Termux adb (already-authorized key) connects -> pins adbd to
#      the durable port 5555.
#   4. VPS2-side: re-establish 5556->5555 ssh-L bridge, reset adb server, connect.
# Exit 0 on success, nonzero on failure (so a cron watchdog can retry).

set -uo pipefail
export HOME=/opt/data/tools/platform-tools
ADB=/opt/data/tools/platform-tools/adb
KEY="-i /opt/data/home/.ssh/phone_ed25519 -o StrictHostKeyChecking=no -o ConnectTimeout=8 -o BatchMode=yes"
PSSH="u0_a363@162.35.173.192"        # phone SSH reverse door
PADB=/data/data/com.termux/files/usr/bin/adb   # Termux adb binary on phone
BRIDGE_PORT=5556
DURABLE=5555

log(){ echo "[$(date '+%F %T')] $*"; }

# --- 0. SSH door up? ---
if ! timeout 6 bash -c "cat < /dev/null > /dev/tcp/162.35.173.192/22070" 2>/dev/null; then
  log "FAIL: ssh door 22070 down (phone not dialing out)."; exit 1
fi

# --- 1. Already healthy? fast-exit if VPS2 adb already sees a device. ---
$ADB kill-server >/dev/null 2>&1; $ADB start-server >/dev/null 2>&1
if $ADB -s 127.0.0.1:${BRIDGE_PORT} shell 'echo OK' >/dev/null 2>&1; then
  log "adb already up via ${BRIDGE_PORT}."; exit 0
fi

# --- 2. Phone-side: pin adbd to durable port 5555. ---
# Try the already-dialed ssh-L bridge listeners first; if phone has no tcp adbd
# yet, connect locally on the phone and tcpip 5555.
phone_pin(){
  ssh $KEY -p 22070 $PSSH "bash -c '
    PADB=/data/data/com.termux/files/usr/bin/adb
    \$PADB start-server >/dev/null 2>&1
    # If a device is already reachable at 5555, pin is done.
    \$PADB connect 127.0.0.1:$DURABLE >/dev/null 2>&1
    if \$PADB -s 127.0.0.1:$DURABLE shell echo OK >/dev/null 2>&1; then exit 0; fi
    # Else discover current adbd port from /proc/net/tcp (no screen reading).
    for port in \$(\$PADB mdns services 2>/dev/null | sed -n \"s/.*port[= ]\\([0-9]*\\).*/\\1/p\" | sort -un); do
      \$PADB connect 127.0.0.1:\$port >/dev/null 2>&1
      if \$PADB -s 127.0.0.1:\$port shell echo OK >/dev/null 2>&1; then
        \$PADB tcpip $DURABLE >/dev/null 2>&1
        exit 0
      fi
    done
    exit 2
  '" 2>&1
}

if ! phone_pin; then
  log "FAIL: could not pin adbd to ${DURABLE} on phone (wireless debugging toggle NOT on? phone key not authorized?)."
  exit 3
fi

# --- 3. VPS2-side: rebuild 5556->5555 bridge. ---
pkill -f "phone_ed25519.*${BRIDGE_PORT}" 2>/dev/null
sleep 1
ssh -N $KEY -p 22070 -L ${BRIDGE_PORT}:127.0.0.1:${DURABLE} $PSSH &
BRIDGE_PID=$!
for i in $(seq 1 10); do
  timeout 2 bash -c "cat < /dev/null > /dev/tcp/127.0.0.1/${BRIDGE_PORT}" 2>/dev/null && break
  sleep 1
done

$ADB kill-server >/dev/null 2>&1; $ADB start-server >/dev/null 2>&1
$ADB connect 127.0.0.1:${BRIDGE_PORT} >/dev/null 2>&1

# --- 4. Verify. ---
if $ADB -s 127.0.0.1:${BRIDGE_PORT} shell 'echo ADB_OK; getprop ro.product.model' 2>&1 | grep -q ADB_OK; then
  log "SUCCESS: adb up via ${BRIDGE_PORT}->phone:${DURABLE} (bridge pid ${BRIDGE_PID})."
  exit 0
else
  log "FAIL: bridge up but adb handshake failed (authorization/offline)."
  exit 4
fi
