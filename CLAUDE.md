# Phone Operations -- Agent Context

This directory manages all phone (CPH2619) operations from VPS2.

## IMMUTABLE RULES

1. **Bank apps = untouchable.** No launch, force-stop, disable, AppOps, data access,
   reinstall for any banking/financial app. This is permanent and enforced across
   all sessions via canonical memory.
2. **GMS = never disable.** `com.google.android.gms` under any circumstance.
   Disabling it breaks Gmail, Tasks, Play Store.
3. **No agent-harness on VPS1** -- ever. All changes to agent-harness go through
   GitHub only (commit+push, user pulls on VPS1).
4. **Dorn for all Google/WhatsApp access.** No direct curl to Google APIs or WA bridges.

## ADB CONNECTION

```
PHONE_ADB=162.35.173.192:5556
ADB_CMD="HOME=/opt/data/tools/platform-tools /opt/data/tools/platform-tools/adb -s 162.35.173.192:5556"
```

Enable a package: `eval "$ADB_CMD shell pm enable <pkg>"`
Disable a package: `eval "$ADB_CMD shell pm disable-user --user 0 <pkg>"`
Check state: `eval "$ADB_CMD shell dumpsys package <pkg> | grep -oE 'enabled=[0-9]'"`
(enabled=0 default/running, enabled=3 disabled-user)

## DEPLOY TARGETS

Lists in `deploy/` are the canonical source of truth. After any change:
1. Update the relevant file in `deploy/`
2. Update `ALLOW_BACK` in `scripts/phone_disable_watchdog.sh`
3. If the package is on the phone, run `pm enable` or `pm disable-user` live

## SCRIPTS (VPS2 side)

| Script | Purpose |
|---|---|
| `phone_adb_vps2_tunnel.sh` | Reverse tunnel: VPS2:5555 -> phone:5555 |
| `phone_tunnel_watchdog.sh` | Keeps reverse tunnel alive |
| `phone_egress_watchdog.sh` | Monitors phone WAN connectivity |
| `phone_state_track.py` | Logs phone screen/AC/battery state |
| `phone_sensor_pull.sh` | Pulls sensor logs from phone |
| `phone_disable_watchdog.sh` | Re-enforcer: stops disabled apps reverting |
| `phone_door_watchdog.sh` | Monitors ADB door liveness |
| `phone_door_*/sh` | Door diagnostics and repair |
| `phone_adb_bridge_watchdog.sh` | Bridges phone ADB to VPS2 |
| `phone_adb_repair.sh` | Repairs broken ADB state |
| `phone_resurrect.sh` | Full phone comm resurrection |
| `phone_supervisor_v4.sh` | VPS2-side supervisor launcher |

## SCRIPTS (Phone side -- Termux)

| Script | Purpose |
|---|---|
| `phone-src/boot_start.sh` | Termux boot: starts sshd + tunnel |
| `phone-src/supervisor.sh` | Termux supervisor: keeps sshd up |
