#!/bin/bash
# Compare the phone on the stock kernel (baseline) with the phone booted on our kernel (verify).
#   kernel-recipe/test-on-device.sh baseline          # on STOCK kernel, before fastboot boot
#   kernel-recipe/test-on-device.sh verify [ko-dir]   # on OUR kernel (after `fastboot boot`)
# ko-dir: host dir with the new modules (can-isotp.ko ...) to push and load; optional.
# Output: kernel/test-<mode>/ ; verify prints a verdict. Needs adb + Magisk su.
set -uo pipefail
MODE="${1:?usage: test-on-device.sh baseline|verify [ko-dir]}"
KO="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
D="$ROOT/kernel/test-$MODE"; B="$ROOT/kernel/test-baseline"
mkdir -p "$D"
sh_() { adb shell "su -c '$1'" 2>/dev/null | tr -d '\r'; }

adb get-state >/dev/null 2>&1 || { echo "!! no device"; exit 2; }
# Let the module's boot scripts finish first. Their logs are written at the END (the Wi-Fi swap ends
# with a ~20 s settle), so "file exists" is not enough: wait for non-empty logs and no swap marker.
M=/data/adb/modules/nethunter-kmods
sh_ "for i in \$(seq 1 180); do { [ ! -f $M/wlan/qca_cld3_wcn7750.ko ] || { [ -s $M/wlan/boot.log ] && [ ! -f $M/wlan/swapping ]; }; } && { [ ! -f $M/gki/kernel.version ] || [ -s $M/gki/boot.log ]; } && break; sleep 1; done" >/dev/null
# dmesg lines are compared without their [timestamp]
nots() { sed 's/^\[[^]]*\] //' "$@"; }
sh_ "cat /proc/version"                         > "$D/version"
sh_ "cat /proc/modules" | awk '{print $1}' | sort > "$D/modules"
sh_ "cat /proc/sys/kernel/tainted"              > "$D/tainted"
sh_ "dmesg" | grep -iE "Unknown symbol|disagrees about version|Invalid module format|module verification failed|EACCES|Permission denied.*module|failed to load|probe of .* failed" > "$D/dmesg-module-errors"
{
  echo "wlan0: $(sh_ "cat /sys/class/net/wlan0/operstate")"
  echo "hci0 : $(sh_ "ls /sys/class/bluetooth 2>/dev/null | tr '\n' ' '")"
  echo "data : $(adb shell getprop gsm.network.type | tr -d '\r') / sim $(adb shell getprop gsm.sim.state | tr -d '\r')"
  echo "boot : $(adb shell getprop sys.boot_completed | tr -d '\r')"
} > "$D/state"

echo "== $MODE"; head -c 160 "$D/version"; echo
echo "modules loaded: $(wc -l < "$D/modules")   tainted: $(cat "$D/tainted")"
cat "$D/state"
echo "module errors in dmesg: $(wc -l < "$D/dmesg-module-errors")"

if [ "$MODE" = verify ]; then
  [ -s "$B/modules" ] || { echo "!! no baseline in $B — run 'baseline' on the stock kernel first"; exit 3; }
  missing="$(comm -23 "$B/modules" "$D/modules")"
  echo "--- modules loaded on stock but NOT on ours: $(printf '%s' "$missing" | grep -c .)"
  printf '%s\n' "$missing" | sed '/^$/d;s/^/  /'
  echo "--- new module errors vs baseline:"
  comm -13 <(nots "$B/dmesg-module-errors" | sort -u) <(nots "$D/dmesg-module-errors" | sort -u) | sed 's/^/  /' | head -30
  if [ -n "$KO" ]; then
    echo "--- loading new modules"
    adb push "$KO"/*.ko /data/local/tmp/ >/dev/null
    for m in can can_raw can-isotp can-j1939 bluetooth bnep usbnet cdc_ether rndis_host cdc-wdm qmi_wwan cdc_mbim; do
      if [ -f "$KO/$m.ko" ]; then r="$(sh_ "insmod /data/local/tmp/$m.ko 2>&1 || echo FAIL")"
      else r="$(sh_ "modprobe -d /system_dlkm/lib/modules $m 2>&1 || modprobe $m 2>&1 || echo FAIL")"; fi
      printf "  %-12s %s\n" "$m" "${r:-ok}"
    done
    sh_ "cat /proc/modules" | grep -E "^(can_isotp|can_j1939|bnep|rndis_host|qmi_wwan|cdc_mbim|cdc_wdm) " | awk '{print "  loaded: "$1}'
  fi
  [ -z "$missing" ] && echo "VERDICT: every stock module loaded" || echo "VERDICT: REGRESSION — see list above"
fi
