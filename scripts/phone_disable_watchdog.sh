#!/usr/bin/env bash
# Phone disable re-enforcer (VPS2). Reapplies pm disable-user in case OEM
# re-enables the apps. Uses the PERMANENT adb door: reverse tunnel maps
# VPS2:5556 -> phone:5555 (adbd fixed on 5555 via `adb tcpip 5555`).
#
# 18-Sep-2026 REWRITE (after 2nd overnight wipe):
#  - REMOVED com.google.android.apps.messaging from TARGETS. It is now the
#    holder of android.app.role.SMS on Android 16 (Google Messages is the only
#    RCS-capable default). Disabling it KILLS OTP/bank SMS delivery. This was a
#    live bug: the old script would have disabled the SMS app on every tick.
#  - TARGETS is now DERIVED from the on-disk debloat list so it can never drift
#    from what was actually disabled. Falls back to the small explicit set.
#  - Added the OTA chain as a hard, always-re-enforced block.
set -u
export HOME=/opt/data/tools/platform-tools
ADB=/opt/data/tools/platform-tools/adb
DOOR="162.35.173.192:5556"
LIST=/opt/data/tmp/phone_deploy/debloat_targets.txt

# Small always-on core set (kept even if the list file is missing).
CORE="com.android.nfc"

# OTA chain: never allowed to come back. com.oplus.cota was uninstalled for
# user 0; the rest are held disabled (they are core system apps that refuse
# uninstall but DO accept disable-user).
OTA="com.oplus.cota com.oplus.ota com.oplus.romupdate com.oplus.sau com.oplus.sauhelper com.oplus.upgradeguide com.oplus.phonemanager"

# NEVER disable these (protected 17-Sep-2026). They are system-uid (1000) Oplus
# framework plumbing for the ColorOS share sheet + MultiApp app-clone chooser.
# Disabling them silently breaks "share image -> pick original vs cloned app":
# the share sheet renders but the MultiAppResolverActivity selector never fires.
# com.oplus.multiapp is the clone service itself - disabling it kills user 999.
PROTECTED="com.oplus.multiapp com.oneplus.oshare com.oplus.appplatform com.oplus.exsystemservice com.android.intentresolver"

# Role holders that must NEVER be disabled (18-Sep-2026). Disabling any of these
# breaks a core function: SMS=OTP/bank delivery, DIALER=calls, BROWSER=webview
# intent target, EMERGENCY=safety, HOME=launcher.
# NOTE 18-Sep-2026: com.google.android.googlequicksearchbox was removed from this
# set. It holds android.app.role.ASSISTANT, but keeping it here made the
# re-enforcer resurrect Google Assistant on every tick (user: "Google assistant
# still there"). Disabling it clears the ASSISTANT role harmlessly - the phone
# simply has no assistant, which is the user's intent. Both Google Assistant
# packages now live in ASSISTANT_KILL below and are re-enforced disabled.
ROLE_PROTECTED="com.google.android.apps.messaging com.google.android.dialer com.android.chrome com.oplus.sos com.android.launcher"

# Google Assistant must stay GONE (18-Sep-2026, explicit user ask). Two packages
# carry it: the standalone app and the Google app that holds the ASSISTANT role.
# Both accept `pm disable-user`; the role clears automatically when the holder is
# disabled. Always re-enforced so no re-enable pass can bring Assistant back.
ASSISTANT_KILL="com.google.android.googlequicksearchbox com.google.android.apps.googleassistant"

# 18-Sep-2026: user asked for the wallpaper selector + theming back. These were
# disabled by the aggressive pass and manually re-enabled. They must never be
# re-disabled, so they are hard-protected here (and absent from the targets list).
#
# 18-Sep-2026 (later): com.google.android.gm ADDED. Gmail kept vanishing because
# it sat in debloat_targets.txt. User needs Gmail on the phone permanently. It is
# now refuse-protected AND self-heal re-enabled on every tick, so a stale list or
# a manual debloat run can no longer take it away. Same for Slack (new install).
ALLOW_BACK="com.google.android.gm com.Slack com.oplus.wallpapers com.oplus.themestore com.oplus.uiengine com.oplus.uxdesign com.oplus.keyguard.personality.clocks com.oplus.keyguard.style.widgets com.android.wallpaper.livepicker com.android.wallpaperpicker com.android.wallpapercropper com.android.wallpaperbackup com.pinterest com.linkedin.android"

# MEDIA_PATH = foreground-service / media-session plumbing. Disabling ANY of
# these breaks YouTube (and other) background audio playback: the app loses its
# media session + playback notification the moment it leaves the foreground.
# Added 18-Sep-2026 after the debloat wrongly disabled mediacontroller and
# audio.effectcenter and broke background playback. NEVER debloat these.
MEDIA_PATH="com.oplus.mediacontroller com.oplus.audio.effectcenter com.oplus.melody com.google.android.youtube"

# PLAYBACK_KEEP = media apps that must be force-ENABLED if found disabled.
PLAYBACK_KEEP="com.oplus.mediacontroller com.oplus.audio.effectcenter com.google.android.youtube"

# TARGETS = whole debloat list (if present) + core + OTA + assistant removal
TARGETS=""
[ -f "$LIST" ] && TARGETS="$(grep -v '^#' "$LIST" 2>/dev/null | tr '\n' ' ')"
TARGETS="$TARGETS $CORE $OTA $ASSISTANT_KILL"

# adb door resolution (18-Sep-2026: mesh-direct works; the VPS2:5556 reverse
# bridge is OFTEN DOWN because the phone-side tunnel drops when the phone is on
# wifi. Try the bridge first, then fall back to the phone's own mesh IP:5555,
# which is reachable whenever the phone is on the mesh/wifi.)
resolve_door(){
  for cand in "$DOOR" "10.7.0.3:5555"; do
    if [ "$($ADB devices | grep "$cand" | grep -c "device")" = "0" ]; then
      $ADB connect "$cand" >/dev/null 2>&1; sleep 2
    fi
    if [ "$($ADB devices | grep "$cand" | grep -c "device")" != "0" ]; then
      echo "door=$cand"; return 0
    fi
  done
  return 1
}
DOOR_LIVE=$(resolve_door) || { echo "adb door down - skipping"; exit 0; }
A="$ADB -s ${DOOR_LIVE#door=}"

dirty=0
for p in $TARGETS; do
  # refuse if protected (ALLOW_BACK/MEDIA_PATH = must never be disabled either)
  for pr in $PROTECTED $ROLE_PROTECTED $ALLOW_BACK $MEDIA_PATH; do
    if [ "$p" = "$pr" ]; then echo "REFUSING (protected): $p"; continue 2; fi
  done
  st=$($A shell dumpsys package "$p" 2>/dev/null | grep -oE 'enabled=[0-9]' | head -1)
  if [ -z "$st" ]; then continue; fi            # not installed
  if [ "$st" != "enabled=0" ] && [ "$st" != "enabled=3" ]; then
    echo "RE-ENABLED -> disabling: $p ($st)"
    $A shell pm disable-user --user 0 "$p" >/dev/null 2>&1
    $A shell am force-stop "$p" >/dev/null 2>&1
    dirty=1
  fi
done

# Self-heal: if any PROTECTED / ROLE_PROTECTED / ALLOW_BACK / MEDIA_PATH package
# got disabled, re-enable it. ALLOW_BACK covers the wallpaper/theming set the
# user asked to have restored; MEDIA_PATH covers the media-session plumbing that
# background playback (YouTube) depends on.
for pr in $PROTECTED $ROLE_PROTECTED $ALLOW_BACK $MEDIA_PATH; do
  st=$($A shell dumpsys package "$pr" 2>/dev/null | grep -oE 'enabled=[0-9]' | head -1)
  if [ "$st" = "enabled=0" ] || [ "$st" = "enabled=3" ]; then
    echo "PROTECTED package was disabled -> re-enabling: $pr"
    $A shell pm enable --user 0 "$pr" >/dev/null 2>&1
    dirty=1
  fi
done

# YouTube background playback needs the app force-enabled AND exempt from
# battery optimisation, or ColorOS/doze suspends its media session at lock.
for pk in $PLAYBACK_KEEP; do
  st=$($A shell dumpsys package "$pk" 2>/dev/null | grep -oE 'enabled=[0-9]' | head -1)
  if [ "$st" = "enabled=3" ] || [ "$st" = "enabled=2" ]; then
    echo "PLAYBACK app disabled -> re-enabling: $pk"
    $A shell pm enable --user 0 "$pk" >/dev/null 2>&1
    dirty=1
  fi
  $A shell cmd deviceidle whitelist "+$pk" >/dev/null 2>&1
done

# Phantom process killer must stay OFF or Android reaps sshd/supervisor.
PK=$($A shell settings get global settings_enable_monitor_phantom_procs 2>/dev/null | tr -d '\r')
if [ "$PK" != "false" ]; then
  echo "phantom-proc killer re-enabled -> turning off"
  $A shell settings put global settings_enable_monitor_phantom_procs false >/dev/null 2>&1
  dirty=1
fi

# OTA gating (18-Sep-2026). The OTA packages themselves are un-disablable:
# com.oplus.ota/romupdate/sau reject `pm disable-user` ("new state: default"),
# reject `pm uninstall --user 0` (DELETE_FAILED_INTERNAL_ERROR) and only ONE of
# them (romupdate) accepts `cmd package suspend`. `pm hide` is a silent no-op on
# Android 16, and per-component disable is refused ("Shell cannot change
# component state"). uid 2000 also lacks MANAGE_APP_OPS_MODES, so appops is out.
# The ONLY durable lever left is the OTA switch settings, which shell CAN write.
# Re-assert them so a wipe/carrier push cannot silently re-arm auto-update.
# NOTE: ro.boot.bootreason showed "reboot,factory_reset" - the wipe was a
# factory_reset boot, so this gating is a mitigation, not a proven barrier.
OTA_KEYS_SECURE="boot_reg_ota can_sau_app_auto_update oplus_customize_ota_patch oplus_customize_cta_update_service oplus_customize_cta_auto_update_virus oplus_customize_cta_update_pictorial oplus_custom_ota_dot_on_launcher com.oplus.ota.detected_status com.oplus.opex.detected_status Setting_HasUpdateAdditionalValues"
# 18-Sep-2026: the CTA/ota_patch switches exist as SHADOW COPIES in the system
# namespace too, and the phone writes THOSE. Verified live: system/
# oplus_customize_ota_patch read 1 while secure/oplus_customize_ota_patch read 0
# - the old watchdog only gated `secure`, so the live toggle silently re-armed.
# Both namespaces must be gated; the UI reads the system copy.
OTA_KEYS_SYSTEM="oplus_customize_ota_patch oplus_customize_cta_update_service oplus_customize_cta_auto_update_virus oplus_customize_cta_update_pictorial oplus_custom_ota_dot_on_launcher com.oplus.opex.downloaded_status"
OTA_KEYS_GLOBAL="can_update_at_night"
assert_key(){ # ns key
  local ns="$1" k="$2" cur
  cur=$($A shell settings get "$ns" "$k" 2>/dev/null | tr -d '\r')
  case "$cur" in
    0|null|"") return 0 ;;   # already gated / not present in this ns
  esac
  echo "OTA gate $ns/$k=$cur -> 0"
  $A shell settings put "$ns" "$k" 0 >/dev/null 2>&1
  dirty=1
}
for k in $OTA_KEYS_SECURE;  do assert_key secure "$k"; done
for k in $OTA_KEYS_SYSTEM;  do assert_key system "$k"; done
for k in $OTA_KEYS_GLOBAL;  do assert_key global "$k"; done

# 18-Sep-2026: the OTA packages sit in the Doze power whitelist (exempt from
# battery optimisation), which is what lets them download in the background.
# Shell CAN remove them from the whitelist (cmd deviceidle needs no special
# permission). Re-asserted every tick so a wipe cannot silently re-arm it.
for p in com.oplus.ota com.oplus.sau com.oplus.romupdate com.oplus.sauhelper; do
  wl=$($A shell "cmd deviceidle whitelist 2>/dev/null" | tr -d '\r' | grep -c "$p")
  if [ "$wl" != "0" ]; then
    echo "OTA $p back in doze whitelist -> removing"
    $A shell "cmd deviceidle whitelist -$p" >/dev/null 2>&1
    dirty=1
  fi
done

# Re-assert `cmd package suspend` on the OTA set where it actually sticks.
for p in com.oplus.romupdate; do
  sus=$($A shell dumpsys package "$p" 2>/dev/null | grep -oE 'suspended=[a-z]+' | head -1)
  if [ "$sus" = "suspended=false" ]; then
    echo "OTA $p un-suspended -> suspending"
    $A shell cmd package suspend --user 0 "$p" >/dev/null 2>&1
    dirty=1
  fi
done

[ "$dirty" = "0" ] && echo "all disables intact"
exit 0
