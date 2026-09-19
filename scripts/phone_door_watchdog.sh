#!/bin/bash
# phone_door_watchdog.sh - self-heals the phone door. Silent while healthy.
#
# WHY (root cause 18-Sep-2026). The WiFi<->mobile-data drop was THREE faults:
#  (1) Termux app gets reaped -> supervisor+sshd+reverse tunnel all die together.
#      Termux:Boot fires only on DEVICE REBOOT, so a plain app kill left the door
#      dead forever. Nothing revived it.
#  (2) adbd (uid shell, oom_score_adj -1000) survives everything on 0.0.0.0:5555,
#      and `run-as com.termux` can run Termux binaries from it. That is the only
#      lever the host has when the stack is dead and nobody is holding the phone.
#  (3) A dead reverse-forward session used to squat VPS2:22070 forever because
#      ClientAliveInterval was 0. Fixed by 92-phone-keepalive.conf (15s x 4).
#
# This script does the job keepalive cannot: revive the Termux stack over adbd
# when it has been reaped, and reap a zombie door-holder if the port never frees.
#
# DESIGN NOTES (learned the hard way):
#  * Liveness probes use the "[x]" bracket trick. A plain `pgrep -f supervisor.sh`
#    matches the run-as WRAPPER SHELL'S OWN command line -> false ALIVE, and the
#    watchdog would never revive anything. Verified reproducible 18-Sep-2026.
#  * This runs inside a container on VPS2. `ss` does NOT work here (no socket
#    visibility), so local state is read via `ps` + functional probes only.
#  * Port 22069 on VPS2 is an UNRELATED service. Never touch it. Only 22070/5556.
#
# Exit: 0 always. Prints only when it repaired something or repair failed.

export HOME=/opt/data/tools/platform-tools
ADB=/opt/data/tools/platform-tools/adb
PHONE=10.7.0.3:5555
SSHKEY=/opt/data/home/.ssh/phone_ed25519      # phone user key (door)
VPS2KEY=/opt/data/home/.ssh/id_ed25519        # VPS2 root key
VPS2=162.35.173.192
SSHUSER=u0_a363
DOORPORT=22070
TB=/data/data/com.termux/files/usr/bin/bash
LOG=/opt/data/scripts/phone_door_watchdog.log
REAP_AGE=900

say(){ echo "$(date '+%F %T'): $*" >> "$LOG"; }
report(){ echo "PHONE DOOR: $*"; }

# ---- 1. Is the adbd path alive? (phone on, mesh up, adbd running) -------------
$ADB connect $PHONE >/dev/null 2>&1
if ! timeout 15 $ADB -s $PHONE shell true >/dev/null 2>&1; then
  say "adbd unreachable at $PHONE - skip (phone off / mesh down; tunnel watchdog owns this)"
  exit 0
fi

# ---- 2. Is the Termux stack alive? Self-immune pgrep (bracket trick) ---------
stack_alive(){
  local r
  r=$(timeout 25 $ADB -s $PHONE shell \
      "run-as com.termux $TB -c 'export PATH=/data/data/com.termux/files/usr/bin:/system/bin; pgrep -f \"su[p]ervisor.sh\" >/dev/null && echo ALIVE || echo DEAD'" \
      2>/dev/null | tr -d '\r' | grep -E 'ALIVE|DEAD' | tail -1)
  [ "$r" = ALIVE ]
}

# ---- 3. Functional door check (port-open is NOT enough) ----------------------
door_works(){
  timeout 20 ssh -i "$SSHKEY" -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null -o ConnectTimeout=8 -o BatchMode=yes \
    -p $DOORPORT $SSHUSER@$VPS2 'exit 0' >/dev/null 2>&1
}

ALIVE_BEFORE=0; stack_alive && ALIVE_BEFORE=1
DOOR_BEFORE=0;  door_works  && DOOR_BEFORE=1

# Fast path: stack alive AND door answers -> healthy, stay silent.
if [ "$ALIVE_BEFORE" = 1 ] && [ "$DOOR_BEFORE" = 1 ]; then
  exit 0
fi

say "unhealthy: stack_alive=$ALIVE_BEFORE door_works=$DOOR_BEFORE - repairing"

# ---- 4. Revive the Termux stack over adbd (no hands on the phone) ------------
if [ "$ALIVE_BEFORE" = 0 ]; then
  timeout 25 $ADB -s $PHONE shell 'am start -n com.termux/.app.TermuxActivity' >/dev/null 2>&1
  sleep 6
  # start_stack.sh double-forks + setsid, so it survives the adb shell exit.
  timeout 60 $ADB -s $PHONE shell \
    "run-as com.termux $TB -c 'export PATH=/data/data/com.termux/files/usr/bin:/system/bin; nohup /data/data/com.termux/files/home/start_stack.sh >/dev/null 2>&1 & sleep 15; echo DONE'" \
    >/dev/null 2>&1
  sleep 8
fi

# ---- 5. Reap a zombie door-holder, but ONLY if the door is truly dead -------
# A live tunnel would make the door work, so if the door is dead, any session
# still holding 22070/5556 and older than REAP_AGE is a zombie. Keepalive
# normally clears these in ~60s; this is the belt-and-braces path.
if ! door_works; then
  KILLED=$(timeout 60 ssh -i "$VPS2KEY" -o StrictHostKeyChecking=no \
    -o ConnectTimeout=10 -o BatchMode=yes root@$VPS2 bash -s <<'EOS' 2>/dev/null
# Map listening sockets on 22070 (0x5636) / 5556 (0x15B4) to owning pids, via
# /proc/net/tcp inodes -> /proc/<pid>/fd symlinks. Portable; no ss/lsof needed.
out=""
inodes=$(awk 'NR>1{split($2,a,":"); if(a[2]=="5636"||a[2]=="15B4") print $10}' \
         /proc/net/tcp /proc/net/tcp6 2>/dev/null)

[ -z "$inodes" ] && { echo ""; exit 0; }

for inode in $inodes; do
  [ -z "$inode" ] && continue
  for link in /proc/[0-9]*/fd/*; do
    [ "$(readlink "$link" 2>/dev/null)" = "socket:[$inode]" ] || continue
    pid=$(echo "$link" | cut -d/ -f3)
    age=$(ps -o etimes= -p "$pid" 2>/dev/null | tr -d ' ')
    [ -z "$age" ] && continue
    if [ "$age" -gt 900 ]; then
      ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
      kill -TERM "$pid" $ppid 2>/dev/null
      out="$out ${pid}(age${age}s)"
    fi
    break
  done
done
echo "$out"
EOS
)
  KILLED=$(echo "$KILLED" | tr -d '\r' | tr -s ' ')
  if [ -n "$KILLED" ] && [ "$KILLED" != " " ]; then
    say "reaped zombie door holder(s):$KILLED"
    sleep 20   # give the phone's supervisor a chance to redial
  fi
fi

# ---- 6. Verify against the ORIGINAL failure, honestly ----------------------
ALIVE_AFTER=0; stack_alive && ALIVE_AFTER=1
DOOR_AFTER=0;  door_works  && DOOR_AFTER=1

if [ "$ALIVE_AFTER" = 1 ] && [ "$DOOR_AFTER" = 1 ]; then
  say "REPAIRED: stack_alive=1 door_works=1"
  if [ "$ALIVE_BEFORE" = 0 ]; then
    report "Termux had been reaped; revived over adb and door restored (no phone interaction needed)"
  else
    report "door was down; recovered (stack_alive=$ALIVE_AFTER door_works=$DOOR_AFTER)"
  fi
else
  say "REPAIR FAILED: stack_alive=$ALIVE_AFTER door_works=$DOOR_AFTER"
  report "door repair FAILED (stack_alive=$ALIVE_AFTER door_works=$DOOR_AFTER) - phone may need a physical check"
fi
exit 0
