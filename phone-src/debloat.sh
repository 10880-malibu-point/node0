#!/data/data/com.termux/files/usr/bin/bash
# Aggressive debloat for the phone node. All reversible with: pm enable <pkg>
# HARD EXCLUSIONS (never disabled): role holders, share-sheet plumbing, our stack,
# comms, GMS/webview/network core, power/security/systemui, and TTS (wake_me.sh).

DISABLE="
com.google.android.apps.docs
com.google.android.apps.maps
com.google.android.apps.photos
com.google.android.apps.tachyon
com.google.android.apps.youtube.music
com.google.android.videos
com.google.android.youtube
com.google.android.apps.nbu.files
com.google.android.apps.wellbeing
com.google.android.apps.subscriptions.red
com.google.android.apps.chromecast.app
com.google.android.apps.adm
com.google.android.gm
com.google.android.calendar
com.google.android.contacts
com.google.android.apps.nbu.paisa.user
com.google.android.apps.restore
com.google.android.apps.setupwizard.searchselector
com.google.android.apps.work.clouddpc
com.google.android.feedback
com.google.android.projection.gearhead
com.google.android.marvin.talkback
com.google.android.accessibility.switchaccess
com.google.android.healthconnect.controller
com.google.android.health.connect.backuprestore
com.google.android.printservice.recommendation
com.google.android.hotspot2.osulogin
com.google.android.partnersetup
com.google.android.onetimeinitializer
com.google.android.setupwizard
com.google.android.ambient.streaming
com.google.android.gms.location.history
com.google.android.googlequicksearchbox
com.oplus.cota
com.oplus.ota
com.oplus.romupdate
com.oplus.sau
com.oplus.sauhelper
com.oplus.upgradeguide
com.oplus.phonemanager
com.oplus.statistics.rom
com.oplus.onetrace
com.oplus.crashbox
com.oplus.logkit
com.oplus.dmp
com.oplus.olc
com.oplus.pantanal.ums
com.oplus.stdid
com.oplus.stdsp
com.oplus.metis
com.oplus.obrain
com.oplus.aiunit
com.oplus.aimemory
com.oplus.aiwriter
com.oplus.cosa
com.google.mainline.telemetry
com.heytap.htms
com.coloros.assistantscreen
com.coloros.childrenspace
com.coloros.colordirectservice
com.coloros.compass2
com.coloros.floatassistant
com.coloros.ocrscanner
com.coloros.ocs.opencapabilityservice
com.coloros.operationManual
com.coloros.scenemode
com.coloros.sceneservice
com.coloros.smartsidebar
com.coloros.translate
com.coloros.translate.engine
com.coloros.video
com.coloros.weather.service
com.oneplus.account
com.oneplus.backuprestore
com.oneplus.brickmode
com.oneplus.colorx
com.oneplus.filemanager
com.oneplus.mall
com.oneplus.membership
com.oneplus.note
com.heytap.accessory
com.heytap.browser
com.heytap.cloud
com.heytap.colorfulengine
com.heytap.market.overlay
com.heytap.mcs
com.heytap.mydevices
com.heytap.pictorial
com.nearme.instant.platform
com.oplus.aod
com.oplus.appbooster
com.oplus.apprecover
com.oplus.appsense
com.oplus.audio.effectcenter
com.oplus.beaconlink
com.oplus.blur
com.oplus.bttestmode
com.oplus.callrecorder
com.oplus.contentportal
com.oplus.engineercamera
com.oplus.engineermode
com.oplus.engineernetwork
com.oplus.games
com.oplus.healthservice
com.oplus.keyguard.personality.clocks
com.oplus.keyguard.style.widgets
com.oplus.lfeh
com.oplus.locationproxy
com.oplus.mediacontroller
com.oplus.melody
com.oplus.nearcomm
com.oplus.omoji
com.oplus.owkservice
com.oplus.pscanvas
com.oplus.riderMode
com.oplus.sandbox.runtime
com.oplus.sense.netprediction
com.oplus.sense.netscore
com.oplus.tai.borderpresearch
com.oplus.tai.wifiqoe
com.oplus.themestore
com.oplus.uiengine
com.oplus.uxdesign
com.oplus.vdc
com.oplus.voice.crs
com.oplus.wallpapers
com.oplus.wifibackuprestore
com.oplus.qualityprotect
com.oplus.postmanservice
com.oplus.plugin
"
# SAFETY: strip anything on the never-touch list regardless of the list above
KEEP="com.google.android.dialer com.google.android.apps.messaging com.android.chrome
com.oplus.sos com.android.launcher com.google.android.inputmethod.latin
com.google.android.tts com.oplus.multiapp com.oneplus.oshare com.oplus.appplatform
com.oplus.exsystemservice com.android.intentresolver com.termux com.termux.boot
com.termux.api com.wireguard.android at.bitfire.davdroid me.mudkip.moememos
com.whatsapp io.element.android.x com.android.shell com.google.android.gms
com.google.android.gsf com.google.android.webview com.oplus.battery
com.oplus.powermonitor com.oplus.notificationmanager com.oplus.securityguard
com.oplus.safecenter com.oplus.securitykeyboard com.oplus.securitypermission
com.oplus.location com.oplus.wirelesssettings com.oplus.motionsense
com.oplus.encryption com.coloros.bootreg com.coloros.activation
com.oplus.camera com.oneplus.deskclock com.oneplus.calculator com.oneplus.gallery"

is_kept(){ for k in $KEEP; do [ "$1" = "$k" ] && return 0; done; return 1; }

OK=0; SKIP=0; FAIL=0; FAILED=""
echo "=== DEBLOAT START $(date '+%F %T') ==="
for p in $DISABLE; do
  if is_kept "$p"; then echo "KEEP-PROTECTED $p"; SKIP=$((SKIP+1)); continue; fi
  # only touch packages that are currently enabled
  st=$(pm list packages -e 2>/dev/null | grep -c "^package:$p$")
  if [ "$st" = "0" ]; then echo "ABSENT $p"; SKIP=$((SKIP+1)); continue; fi
  out=$(pm disable-user --user 0 "$p" 2>&1)
  if echo "$out" | grep -qiE "new state: disabled"; then
    echo "DISABLED $p"; OK=$((OK+1))
  else
    echo "FAIL $p :: $out"; FAIL=$((FAIL+1)); FAILED="$FAILED $p"
  fi
done
echo "=== RESULT: disabled=$OK skipped=$SKIP failed=$FAIL ==="
[ -n "$FAILED" ] && echo "FAILED_LIST:$FAILED"
echo "=== OTA packages state after run ==="
for o in com.oplus.cota com.oplus.ota com.oplus.romupdate com.oplus.sau com.oplus.phonemanager; do
  pm list packages -d 2>/dev/null | grep -q "^package:$o$" && echo "  DISABLED $o" || echo "  STILL ENABLED $o"
done
echo "=== DEBLOAT END $(date '+%F %T') ==="
