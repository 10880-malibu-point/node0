#!/data/data/com.termux/files/usr/bin/sh
# Diagnose why the reverse tunnel fails. Run as u0_a363.
export PREFIX=/data/data/com.termux/files/usr
export HOME=/data/data/com.termux/files/home
export LD_LIBRARY_PATH=$PREFIX/lib
export TMPDIR=$PREFIX/tmp
export PATH=$PREFIX/bin:/system/bin

HOST=162.35.173.192
KEY=$HOME/.ssh/id_phone_reverse

echo "=== whoami ==="
whoami 2>/dev/null || id -un 2>/dev/null

echo "=== 1. can we reach VPS2:22 ? ==="
timeout 8 sh -c "exec 3<>/dev/tcp/$HOST/22" 2>&1 && echo "port 22 OPEN" || echo "port 22 UNREACHABLE"
exec 3>&- 3<&- 2>/dev/null

echo "=== 2. ssh version ==="
$PREFIX/bin/ssh -V 2>&1

echo "=== 3. key perms ==="
ls -la $KEY 2>&1

echo "=== 4. plain ssh auth test (no forward) ==="
timeout 25 $PREFIX/bin/ssh -i $KEY \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10 -o BatchMode=yes \
  -p 22 root@$HOST 'echo AUTH_OK; hostname' 2>&1

echo "=== 5. reverse forward attempt on 22070 (verbose) ==="
timeout 30 $PREFIX/bin/ssh -i $KEY \
  -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o ConnectTimeout=10 -o BatchMode=yes \
  -o ExitOnForwardFailure=yes \
  -N -T -v \
  -R 0.0.0.0:22070:127.0.0.1:8022 \
  -p 22 root@$HOST 2>&1 | grep -iE "forward|refus|fail|denied|error|debug1: Remote|Entering|Authenticated" | head -25

echo "=== 6. is local sshd 8022 up? ==="
timeout 4 sh -c "exec 3<>/dev/tcp/127.0.0.1/8022" 2>&1 && echo "8022 OPEN" || echo "8022 CLOSED"
exec 3>&- 3<&- 2>/dev/null
