# Phone Operations

Manages the OnePlus CPH2619 (CPH2619) running ColorOS: ADB access, debloat,
egress tunnel, door monitoring, sensor pull, and Termux on-phone boot/supervisor.

## Directory Structure

```
node0/
  README.md              -- this file (phone ops overview)
  CLAUDE.md              -- agent context for this directory
  RESTORE.md             -- step-by-step phone rebuild procedure
  deploy/                -- debloat package lists (canonical, VPS2-referenced)
  phone-src/             -- scripts that run ON the phone (Termux boot/supervisor)
  scripts/               -- scripts that run ON VPS2 (adb/watchdogs)
  state/                 -- full state snapshot (packages/roles/settings/ota/keys)
```

## Origin / History

Moved out of `agent-harness/phone-ops` on 30-Sep-2026 (repo `10880-malibu-point/node0`
is now the single home for CPH2619 phone management). Earlier archives folded in:
- `/opt/data/phone-resilience/` (Sep 11, 2026)
- `/opt/data/infra-repos/phone-egress/` (Sep 11, 2026)

The VPS2 live scripts live at `/opt/data/scripts/*.sh` (identical bytes to
`scripts/` here) and are what the cron jobs run; `scripts/` is the canonical copy.

## How It Works

```
VPS2 (162.35.173.192)
  |
  +-- scripts/phone_adb_vps2_tunnel.sh     -- reverse tunnel: VPS2:5555 -> phone:5555
  +-- scripts/phone_tunnel_watchdog.sh     -- keeps the reverse tunnel alive
  +-- scripts/phone_egress_watchdog.sh     -- monitors phone WAN connectivity
  +-- scripts/phone_state_track.py         -- logs phone screen/AC/battery state
  +-- scripts/phone_sensor_pull.sh         -- pulls sensor logs from phone
  +-- scripts/phone_disable_watchdog.sh    -- re-enforcer: prevents disabled apps reverting
  +-- scripts/phone_door_watchdog.sh       -- monitors ADB door liveness
  +-- scripts/phone_door_*/                -- door diagnostics and repair
  +-- scripts/phone_adb_bridge_watchdog.sh -- bridges phone ADB to VPS2
  +-- scripts/phone_adb_repair.sh         -- repairs broken ADB state
  +-- scripts/phone_adbd_ensure.sh         -- ensures adbd is running on phone
  +-- scripts/phone_adbd_forensics.sh      -- forensic analysis of adbd state
  +-- scripts/phone_check_now.sh           -- one-shot phone state snapshot
  +-- scripts/phone_resurrect.sh           -- full phone comm resurrection
  +-- scripts/phone_supervisor_v4.sh       -- VPS2-side supervisor launcher
  |
  +-- deploy/debloat_targets.txt           -- packages to disable (sweep target)
  +-- deploy/disabled_final.txt           -- audited disabled set
  +-- deploy/disabled_now.txt             -- current live disabled set
  +-- deploy/pkgs_enabled.txt             -- packages confirmed enabled
  +-- deploy/drawer.txt                   -- app drawer inventory

Phone (CPH2619, 162.35.173.192:5556)
  |
  +-- phone-src/boot_start.sh             -- Termux boot: starts sshd + tunnel
  +-- phone-src/supervisor.sh             -- Termux supervisor: keeps sshd up
```

## Connection Paths

ADB access (uid 2000 shell):
- Direct: `adb -s 162.35.173.192:5556` (phone reachable on WAN)
- Via reverse tunnel: `adb -s 162.35.173.192:5555` -> phone:5555

SSH access (phone Termux sshd, port 22070):
- `ssh -p 22070 -i ~/.ssh/phone_ed25519 u0_a612@162.35.173.192`

## Key Constants

```
PHONE_HOST=162.35.173.192
PHONE_ADB_PORT=5556
PHONE_SSH_PORT=22070
VPS2_ADB_LISTEN=162.35.173.192:5555
ADB_KEY=/opt/data/home/.ssh/id_ed25519
PHONE_SSH_KEY=/opt/data/home/.ssh/phone_ed25519
```

## Debloat Protection (ALLOW_BACK)

Packages in `ALLOW_BACK` within `phone_disable_watchdog.sh` are protected:
they can never be disabled by the watchdog cron, and if disabled will be
auto-re-enabled. Current ALLOW_BACK:
```
com.google.android.gm com.Slack com.oplus.wallpapers com.oplus.themestore
com.oplus.uiengine com.oplus.uxdesign com.oplus.keyguard.personality.clocks
com.oplus.keyguard.style.widgets com.android.wallpaper.livepicker
com.android.wallpaperpicker com.android.wallpapercropper com.android.wallpaperbackup
com.pinterest com.linkedin.android
```

## Security Rules

- Bank apps are completely off-limits: no launch, force-stop, disable, AppOps,
  reinstall, data access, or any other interaction. Canonical memory enforces
  this across all sessions.
- `com.google.android.gms` (GMS) must never be disabled -- it breaks Gmail,
  Tasks, Play Store, and all Google apps.
- Never SSH to or touch agent-harness on VPS1 directly.
