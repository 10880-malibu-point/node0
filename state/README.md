# State snapshot - OnePlus CPH2619 (node0)

Captured **2026-09-30** via adb (reverse door `162.35.173.192:5556`, mesh door `10.7.0.3:5555`).
This directory is the restore reference: if the phone is wiped or rebuilt, read
`RESTORE.md` first, then use these files as the target state.

## Device

- **model**: CPH2619
- **device**: OP5D49L1
- **serial**: 79e6e520
- **android_version**: 16
- **display_id**: CPH2619_16.0.5.1200(EX01)
- **oplus_os**: V16.0.0
- **build_incremental**: U.R4T2.1a9ba23_a93568_a4472c
- **bootreason**: reboot,factory_reset

## Files

| File | Contents |
|---|---|
| `device.json` | model/build/serial/doors, capture time |
| `packages_all.txt` | every package seen (`pm list packages -f`), 467 |
| `packages_enabled.txt` | enabled now, 352 |
| `packages_disabled.txt` | disabled-user now, 115 - the target debloat state |
| `packages_thirdparty.txt` | sideloaded/user apps, 59 |
| `thirdparty_versions.txt` | third-party packages with versionCode (reinstall pins) |
| `packages_dualapp_user999.txt` | dual-app (clone) user 999 set, 14 incl. cloned WhatsApp |
| `packages_paths.txt` | pkg -> apk path + classification |
| `role_holders.json` | Android role holders, 20 (SMS/DIALER/HOME/BROWSER...) |
| `settings_global/secure/system.txt` | full settings dumps, 350/444/468 keys |
| `ota_gates.json` | OTA/update gate keys, 44 (must re-zero after restore) |
| `termux_packages.txt` | Termux dpkg list, 89 pkgs (the on-phone daemon stack) |
| `access_keys.json` | VPS2-side key fingerprints for adb + reverse-tunnel SSH |

## Restored role holders (must match after restore)

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

## ALLOW_BACK (never disabled, 19 pkgs)

`com.Slack` `com.android.wallpaper.livepicker` `com.android.wallpaperbackup` `com.android.wallpapercropper` `com.android.wallpaperpicker` `com.google.android.apps.docs` `com.google.android.apps.maps` `com.google.android.apps.tasks` `com.google.android.calendar` `com.google.android.gm` `com.linkedin.android` `com.oneplus.note` `com.oplus.keyguard.personality.clocks` `com.oplus.keyguard.style.widgets` `com.oplus.themestore` `com.oplus.uiengine` `com.oplus.uxdesign` `com.oplus.wallpapers` `com.pinterest`

## BANNED (remove-on-sight, 1)

`mark.via`

## Third-party apps (59) - reinstall after wipe

`at.bitfire.davdroid` `com.KatanLabs.tilematchpuzzlemaster` `com.Slack` `com.agoda.mobile.consumer` `com.akylas.documentscanner` `com.application.zomato` `com.beemdevelopment.aegis` `com.brave.browser` `com.byterdevs.rsswidget` `com.chess` `com.coloros.translate` `com.duckduckgo.mobile.android` `com.facebook.katana` `com.fitbit.FitbitMobile` `com.github.android` `com.github.catfriend1.syncthingfork` `com.google.android.apps.adm` `com.google.android.apps.chromecast.app` `com.google.android.apps.docs` `com.google.android.apps.docs.editors.docs` `com.google.android.apps.docs.editors.sheets` `com.google.android.apps.subscriptions.red` `com.google.android.apps.tasks` `com.google.android.apps.translate` `com.google.android.contactkeys` `com.google.android.safetycore` `com.google.android.verifier` `com.google.android.videos` `com.heytap.pictorial` `com.katanlabs.bubblepop` `com.katanlabs.wordconnectwondersofview` `com.makemytrip` `com.microsoft.android.smsorganizer` `com.myairtelapp` `com.myntra.android` `com.netflix.mediaclient` `com.oneplus.backuprestore` `com.oneplus.brickmode` `com.oneplus.mall` `com.oneplus.note` `com.onlyoffice.documents` `com.openai.chatgpt` `com.oplus.riderMode` `com.phonepe.app` `com.pinterest` `com.rapido.passenger` `com.termux` `com.termux.api` `com.termux.boot` `com.whatsapp` `com.wireguard.android` `cyou.sk5s.app.weread` `indwin.c3.shareapp` `me.mudkip.moememos` `moe.sable.client` `net.oneplus.forums` `net.oneplus.widget` `org.fdroid.fdroid` `org.handmadeideas.floccus`

## Dual apps / user 999 (14)

`android` `com.android.providers.media` `com.facebook.appmanager` `com.facebook.services` `com.facebook.system` `com.google.android.as` `com.google.android.ext.services` `com.google.android.gms` `com.google.android.gsf` `com.google.android.permissioncontroller` `com.google.android.permissioncontroller.overlay.oplus` `com.google.android.webview` `com.oplus.securitypermission` `com.whatsapp`

## Termux packages (89) - reinstall via pkg after Termux re-setup

`abseil-cpp` `android-tools` `apt` `bash` `brotli` `bzip2` `ca-certificates` `command-not-found` `coreutils` `curl` `dash` `debianutils` `dialog` `diffutils` `dos2unix` `dpkg` `ed` `findutils` `fmt` `gawk` `gpgv` `grep` `gzip` `inetutils` `krb5` `ldns` `less` `libandroid-glob` `libandroid-selinux` `libandroid-support` `libassuan` `libbz2` `libc++` `libcap-ng` `libcurl` `libdb` `libedit` `libevent` `libgcrypt` `libgmp` `libgnutls` `libgpg-error` `libiconv` `libidn2` `liblz4` `liblzma` `libmd` `libmpfr` `libnettle` `libnghttp2` `libnghttp3` `libnpth` `libprotobuf` `libresolv-wrapper` `libsmartcols` `libssh2` `libtirpc` `libunbound` `libunistring` `lsof` `nano` `ncurses` `net-tools` `openssh` `openssh-sftp-server` `openssl` `patch` `pcre2` `procps` `psmisc` `readline` `resolv-conf` `sed` `tar` `termux-am` `termux-am-socket` `termux-api` `termux-auth` `termux-core` `termux-exec` `termux-keyring` `termux-licenses` `termux-tools` `unzip` `util-linux` `xxhash` `xz-utils` `zlib` `zstd`

## Watchouts

- Bank apps are off-limits: never launch/force-stop/disable/reinstall them.
- `com.google.android.gms` must stay enabled (Gmail/Tasks/Play Store depend on it).
- SMS role holder is `com.microsoft.android.smsorganizer` (NOT Google Messages) -
  keep it enabled or OTP delivery breaks.
- OTA packages (`com.oplus.ota`/`sau`/`romupdate`) refuse disable; the durable
  lever is the settings keys in `ota_gates.json` - re-zero them via
  `scripts/phone_disable_watchdog.sh` (it runs every 6h).
- app-clone UIDs (999xxxxx) bypass WireGuard routing; expected, not a bug.
