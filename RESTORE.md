# RESTORE.md - rebuild the OnePlus CPH2619 (node0) from scratch

Use this after a wipe, factory reset, or dead phone. Read `state/README.md` for
the full snapshot reference; this file is the ordered procedure.

Snapshot date: 2026-09-30T17:21:46+00:00. Device: CPH2619 / CPH2619_16.0.5.1200(EX01) /
Android 16, serial `79e6e520`.

## 0. Preconditions

- VPS2 reverse doors: ssh `22070` (phone sshd) and adb `5556` (phone adbd 5555).
- VPS2 keys: `/opt/data/home/.ssh/phone_ed25519` (fingerprint in
  `state/access_keys.json`) is the reverse-tunnel key; the phone keeps its
  private copy at `$HOME/.ssh/id_phone_reverse`.
- ADB client: `HOME=/opt/data/tools/platform-tools /opt/data/tools/platform-tools/adb`.
- All repo scripts run from `/opt/data/node0` (clone of
  `github.com/10880-malibu-point/node0`).

## 1. Factory-fresh phone, minimal setup

1. Complete Android/OOBE setup, sign into Google (needed for Play reinstalls).
2. Enable Developer options -> USB debugging.
3. Install Termux (F-Droid build, `com.termux`), Termux:Boot, Termux:API,
   WireGuard from Play/F-Droid.
4. On the phone, generate the reverse key (or restore from VPS2 backup):
   ```sh
   pkg install openssh
   ssh-keygen -t ed25519 -f $HOME/.ssh/id_phone_reverse -N ''
   # push the .pub to VPS2 authorized_keys and vice versa
   ```
5. From Termux, pin adbd so the reverse door survives:
   ```sh
   adb tcpip 5555   # run once after first USB/wifi pairing
   ```

## 2. Restore the phone-side stack

Everything below is in `phone-side/` (12 files).

```sh
# on the phone (Termux), or via run-as com.termux from adb:
mkdir -p $HOME/.termux/boot
cp phone-side/boot/00_boot_start.sh $HOME/.termux/boot/
cp phone-side/*.sh $HOME/
chmod +x $HOME/*.sh $HOME/.termux/boot/*.sh
cp phone-side/properties/termux.properties $HOME/.termux/termux.properties

# Termux packages (89 - see state/termux_packages.txt):
pkg install openssh curl android-tools coreutils procps psmisc \
            termux-api termux-tools nano tar unzip

# bring the whole stack up (sshd 8022 + reverse tunnel 22070/5556 + adbd pin):
$HOME/phone_bringup.sh
```

Verify from VPS2:

```sh
# ssh door answers a banner
exec 3<>/dev/tcp/127.0.0.1/22070; head -n 1 <&3        # SSH-2.0-OpenSSH_*
# adb door is live
HOME=/opt/data/tools/platform-tools /opt/data/tools/platform-tools/adb devices
```

`supervisor.sh` (launched by the boot entry) keeps sshd + both reverse
forwards alive; `phone_watchdog.sh` and `phone_wake_scheduler.sh` keep it
revivable from the phone side, VPS2 crons keep it revivable from the host side.

## 3. Reinstall apps

1. **Third-party (59):** reinstall from Play/F-Droid.
   Version pins are in `state/thirdparty_versions.txt` (versionCode per pkg).
   Key ones: Termux trio, WireGuard, DAVx5, Moememos, Slack, WhatsApp,
   Pinterest, Aegis, Syncthing-Fork, Floccus, PhonePe, SMS Organizer, Mull.
2. **Dual apps (user 999, 14):** re-enable via Settings -> App clone
   (cloned WhatsApp is in this set). Clone UIDs bypass WireGuard routing -
   expected, not a bug.
3. **Google core:** GMS must be enabled (`com.google.android.gms`).
   Gmail/Maps/Tasks/Docs/Calendar are in ALLOW_BACK - never disable them.

## 4. Apply the debloat state

The target disabled set is `state/packages_disabled.txt` (115 pkgs).

```sh
# run the re-enforcer (it reads deploy/disabled_baseline.txt + banned.txt)
/opt/data/node0/scripts/phone_disable_watchdog.sh
```

It will:
- force-remove anything in `deploy/banned.txt` (`mark.via`) on sight;
- disable every baseline pkg not already `enabled=3`;
- refuse + self-heal anything in PROTECTED / ROLE_PROTECTED / ALLOW_BACK /
  MEDIA_PATH;
- force-enable `PLAYBACK_KEEP` (media plumbing) and re-assert the doze
  whitelist for playback apps;
- turn the phantom-process killer off (or Android reaps sshd);
- re-zero all OTA gate keys (secure + system + global).

Check the result:

```sh
pm list packages -d | wc -l      # expect 115
pm list packages -d | sort > /tmp/now.txt
diff /tmp/now.txt state/packages_disabled.txt
```

## 5. Restore OTA gating

OTA packages refuse disable/uninstall; only settings keys work. The watchdog
re-zeroes them every tick, but after a wipe assert them once by hand:

```sh
for kv in secure/boot_reg_ota secure/can_sau_app_auto_update \
          secure/oplus_customize_ota_patch secure/oplus_customize_cta_update_service \
          secure/oplus_customize_cta_auto_update_virus secure/oplus_customize_cta_update_pictorial \
          secure/oplus_custom_ota_dot_on_launcher secure/com.oplus.ota.detected_status \
          system/oplus_customize_ota_patch system/oplus_customize_cta_update_service \
          system/com.oplus.opex.downloaded_status global/can_update_at_night; do
  ns=${kv%%/*}; k=${kv#*/}
  settings put "$ns" "$k" 0
done
cmd deviceidle whitelist -com.oplus.ota -com.oplus.sau \
  -com.oplus.romupdate -com.oplus.sauhelper
cmd package suspend --user 0 com.oplus.romupdate
```

Full key list (44 keys, live values): `state/ota_gates.json`.

## 6. Restore roles

The debloat disables Assistant packages; other roles should fall back
automatically when their holder is installed. Verify the critical ones:

- `android.app.role.BROWSER` -> `com.duckduckgo.mobile.android`
- `android.app.role.DIALER` -> `com.google.android.dialer`
- `android.app.role.EMERGENCY` -> `com.oplus.sos`
- `android.app.role.HOME` -> `com.android.launcher`
- `android.app.role.SMS` -> `com.microsoft.android.smsorganizer`
- `android.app.role.SYSTEM_ACTIVITY_RECOGNIZER` -> `com.google.android.gms`
- `android.app.role.SYSTEM_AUDIO_INTELLIGENCE` -> `com.google.android.as`
- `android.app.role.SYSTEM_BLUETOOTH_STACK` -> `com.android.bluetooth`
- `android.app.role.SYSTEM_COMPANION_DEVICE_PROVIDER` -> `com.google.android.gms`
- `android.app.role.SYSTEM_CONTACTS` -> `com.google.android.contacts`
- `android.app.role.SYSTEM_DOCUMENT_MANAGER` -> `com.google.android.documentsui`
- `android.app.role.SYSTEM_GALLERY` -> `com.oneplus.gallery`
- `android.app.role.SYSTEM_NOTIFICATION_INTELLIGENCE` -> `com.google.android.as`
- `android.app.role.SYSTEM_SETTINGS_INTELLIGENCE` -> `com.android.settings.intelligence`
- `android.app.role.SYSTEM_SHELL` -> `com.android.shell`
- `android.app.role.SYSTEM_SPEECH_RECOGNIZER` -> `com.google.android.tts`
- `android.app.role.SYSTEM_TEXT_INTELLIGENCE` -> `com.google.android.as`
- `android.app.role.SYSTEM_UI` -> `com.android.systemui`
- `android.app.role.SYSTEM_UI_INTELLIGENCE` -> `com.google.android.as`
- `android.app.role.SYSTEM_VISUAL_INTELLIGENCE` -> `com.aiunit.aon`

```sh
cmd role get-role-holders --user 0 android.app.role.SMS   # must be SMS Organizer
```

## 7. VPS2-side verification checklist

```sh
# 1. doors up
HOME=/opt/data/tools/platform-tools /opt/data/tools/platform-tools/adb devices
# 2. disabled set matches snapshot
# 3. watchdog clean run (last line: 'all disables intact')
/opt/data/node0/scripts/phone_disable_watchdog.sh
# 4. termux roundtrip
ssh -p 22070 -i /opt/data/home/.ssh/phone_ed25519 u0_a363@162.35.173.192 'echo OK'
# 5. sensor/state crons green (phone-state-track, phone-sensor-pull)
```

## 8. Hard rules (never break these)

1. **Bank apps: completely off-limits.** No launch, force-stop, disable,
   AppOps, reinstall, data access - ever.
2. **`com.google.android.gms` must stay enabled** (Gmail/Tasks/Play Store).
3. **SMS role = `com.microsoft.android.smsorganizer`.** Disabling it kills
   OTP/bank SMS delivery.
4. **Share-sheet plumbing never disabled:** `com.oplus.multiapp`,
   `com.oneplus.oshare`, `com.oplus.appplatform`, `com.oplus.exsystemservice`,
   `com.android.intentresolver` (system-uid 1000, breaks app-clone chooser).
5. **Never `pm uninstall` system apps** - disable-user only, always reversible.
6. **Dual apps bypass WireGuard** - structural, no no-root fix.

## Reference

- Snapshot: `state/README.md` + `state/*.txt|json`
- Watchdog (re-enforcer): `scripts/phone_disable_watchdog.sh`
- Phone-side boot/supervisor: `phone-side/boot/00_boot_start.sh`,
  `phone-side/supervisor.sh`, `phone-side/phone_bringup.sh`
- Debloat target list: `deploy/disabled_baseline.txt` (live baseline),
  `deploy/debloat_targets.txt` (fallback), `deploy/banned.txt`
- Full procedure + pitfalls: `README.md` (this repo), `CLAUDE.md`
