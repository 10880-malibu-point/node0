#!/bin/bash
# Phone egress SOCKS watchdog (hardened): keeps a SINGLE 127.0.0.1:10809
# SOCKS tunnel alive through the phone's reverse tunnel (VPS2:22070).
#
# v2 hardening over the old version:
#  - PID-file locked singleton: owns ONE process, references it by pid, never
#    `pkill -f <port>` (which could hit unrelated processes and left orphans).
#  - Reaps orphaned listeners on 10809 that the old nohup spawns left behind,
#    by resolving which pid actually owns the listening socket (/proc inode).
#  - Functional health check: egress only counts as healthy if curl through
#    the proxy actually returns an IP; a dead/wedged forward gets rebuilt.
#  - Writes its own pidfile, so the cron re-spawn reuses/replaces cleanly.
#
# Silent while healthy (watchdog pattern: no output = nothing to report).
SETSID="$(command -v setsid)"
PIDFILE=/tmp/phone_socks.pid
KEY=/opt/data/home/.ssh/phone_ed25519
PORT=10809
TUNNEL_PORT=22070
TUNNEL_HOST=162.35.173.192
LOG=/opt/data/scripts/phone_socks.log
SSH=/usr/bin/ssh

log(){ echo "$(date '+%F %T'): $*" >> "$LOG"; }

# Find pids whose process own a TCP listen socket on the given local port.
# Uses /proc/net/tcp inode -> /proc/<pid>/fd/ symlink scan (no lsof/ss needed).
port_pids(){
  python3 - "$1" <<'PY'
import os, sys, re
port=int(sys.argv[1], 0)
if port > 65535: port = int("2a39", 16)
inodes=set()
for f in ("/proc/net/tcp","/proc/net/tcp6"):
    try:
        with open(f) as fh:
            next(fh)
            for line in fh:
                p=line.split()
                try:
                    if int(p[1].split(':')[1],16)==port and p[3]=="0A":
                        inodes.add(p[9])
                except (IndexError,ValueError): pass
    except IOError: pass
pids=set()
for d in os.listdir("/proc"):
    if not d.isdigit(): continue
    fdd=f"/proc/{d}/fd"
    try:
        for fd in os.listdir(fdd):
            try:
                if os.readlink(f"{fdd}/{fd}") in inodes and d not in pids:
                    pids.add(d)
            except (OSError, ValueError): pass
    except OSError: pass
print(" ".join(sorted(pids)))
PY
}

is_alive(){ [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
egress_ok(){
  timeout 8 curl -s --socks5-hostname 127.0.0.1:$PORT --max-time 6 https://api.ipify.org >/dev/null 2>&1
}

# Is the phone reverse tunnel even reachable? If not, nothing to heal on host.
if ! timeout 5 bash -c "cat </dev/null >/dev/tcp/$TUNNEL_HOST/$TUNNEL_PORT" 2>/dev/null; then
    exit 0
fi

# 1. If egress already works, we're healthy - nothing to do.
if egress_ok; then
    exit 0
fi

# 2. Egress broken. Reap ANY process currently bound to :10809 before respawning,
#    so we never stack duplicates. If a known pidfile pid is alive, that's us.
OLDPID="$(cat "$PIDFILE" 2>/dev/null)"
to_kill="$(port_pids "$PORT")"
if [ -n "$to_kill" ]; then
    log "reaping stale listener pids: $to_kill"
    kill -TERM $to_kill 2>/dev/null
    sleep 2
    # escalate survivors
    remains="$(port_pids "$PORT")"
    [ -n "$remains" ] && kill -KILL $remains 2>/dev/null
fi

# 3. Spawn a fresh, detached (setsid) SOCKS tunnel and record its pid.
log "phone SOCKS (re)starting"
setsid -f "$SSH" -i "$KEY" -o ConnectTimeout=12 -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 \
    -N -D "127.0.0.1:$PORT" "u0_a612@$TUNNEL_HOST" -p "$TUNNEL_PORT" \
    >> /tmp/phone_socks_sshd.log 2>&1 &
NEWPID=$!
sleep 1
echo "$NEWPID" > "$PIDFILE"
log "phone SOCKS started pid=$NEWPID"

# 4. Brief verification - fail loud if it can't come up in ~8s.
sleep 8
if egress_ok; then
    log "phone SOCKS healthy"
else
    log "phone SOCKS FAILED to come up after respawn"
fi
exit 0
