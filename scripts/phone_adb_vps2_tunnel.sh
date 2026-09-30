#!/bin/bash
# Keep VPS2:22070 forward tunnel alive: VPS2 -> (sys0 mesh) -> phone adb :5555
# Persistent adb reach from VPS2 independent of LAN. Relies on sys0 already
# doing persistent adb connect 192.168.1.148:5555.
# Silent while healthy; restarts the SSH forward only when port 22070 is down.
TARGET=127.0.0.1:22070
SSHKEY=/opt/data/home/.ssh/id_ed25519
SSH_HOST=hermes@10.7.0.2
PHONE_ADB=192.168.1.148:5555
LOG=/tmp/vps2_phone_adb_tunnel.log

# Already listening -> healthy, stay silent
if timeout 3 bash -c "cat </dev/null >/dev/tcp/127.0.0.1/22070" 2>/dev/null; then
    exit 0
fi

# sys0 must be up enough to hold the mesh ssh
if ! timeout 6 ssh -o BatchMode=yes -o ConnectTimeout=5 -i "$SSHKEY" "$SSH_HOST" 'exit 0' >/dev/null 2>&1; then
    exit 0  # sys0 unreachable - nothing to do, stay quiet
fi

# Port down + sys0 up -> restart the forward tunnel
pkill -f "22070:192.168.1.148:5555" 2>/dev/null
sleep 1
nohup ssh -i "$SSHKEY" -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -o ExitOnForwardFailure=yes \
    -N -L 22070:$PHONE_ADB "$SSH_HOST" > "$LOG" 2>&1 &
echo "$(date '+%F %T'): phone-adb forward tunnel restarted" >> /opt/data/gateway-starts.log
exit 0
