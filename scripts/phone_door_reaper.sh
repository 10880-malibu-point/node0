#!/usr/bin/env bash
# VPS2-side reverse-door orphan reaper (18-Sep-2026).
#
# PROBLEM: when the phone's reverse tunnel dies without a clean TCP teardown
# (phone reboot, radio drop, app killed), sshd on VPS2 does NOT reap the
# session. The orphaned sshd-session keeps holding :22070 and :5556 for hours.
# The phone's replacement tunnel then fails with
#   "remote port forwarding failed for listen port 22070"
# and, because the phone runs with ExitOnForwardFailure=yes, the tunnel exits
# immediately. Net effect: both doors stay dead until something frees the port.
#
# FIX (key-independent, auth-free): probe the door with a raw TCP banner read.
# The phone runs OpenSSH, so a LIVE door answers "SSH-2.0-OpenSSH_*" within a
# second. An orphaned listener bound to a dead forward answers nothing. If the
# banner does not arrive, the listener is an orphan -> kill it so the phone's
# supervisor can rebind on its next 60s tick.
#
# Safe: only kills sshd-session PIDs that own the port AND fail the banner probe.
# Never touches the main sshd listener (pid of `sshd: /usr/sbin/sshd -D`).
set -u
DOOR_SSH=22070
DOOR_ADB=5556
LOG=/var/log/phone_door_reaper.log
log(){ echo "$(date '+%F %T'): $*" >> "$LOG" 2>/dev/null; }

# Raw banner probe: 1 = live phone sshd behind the door, 0 = orphan/dead.
banner_ok() {
  local b
  b=$(timeout 6 bash -c "exec 3<>/dev/tcp/127.0.0.1/$1; timeout 4 head -n 1 <&3" 2>/dev/null | tr -d '\r')
  case "$b" in SSH-2.0-OpenSSH*) return 0;; *) return 1;; esac
}

holders(){ ss -ltnp 2>/dev/null | grep -E ":$1[[:space:]]" \
  | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u; }

is_orphan_adb() { # $1=pid : live sessions have an ESTABLISHED tcp peer
  ss -tnp 2>/dev/null | grep -q "pid=$1," && return 1 || return 0; }

killed=0

# --- SSH door: authoritative banner probe ---
for p in $(holders $DOOR_SSH); do
  if banner_ok $DOOR_SSH; then
    continue                     # live tunnel, leave it
  fi
  log "22070 held by pid $p but no SSH banner -> orphan, killing"
  kill -9 "$p" 2>/dev/null && killed=1
done

# --- adb door: no banner exists; use ESTABLISHED-peer heuristic ---
for p in $(holders $DOOR_ADB); do
  if is_orphan_adb "$p"; then
    log "5556 held by pid $p with no ESTABLISHED peer -> orphan, killing"
    kill -9 "$p" 2>/dev/null && killed=1
  fi
done

if [ "$killed" = "1" ]; then
  sleep 3
  log "reap done; 22070 listener count=$(ss -ltn 2>/dev/null | grep -c ':22070')"
fi
exit 0
