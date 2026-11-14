#!/bin/bash
# Кладе зібраний драйвер вбудованого Wi-Fi qca_cld3_wcn7750.ko у модуль nethunter-kmods
# (тека wlan/), разом зі значеннями прив'язки до прошивки, щоб драйвер увійшов у той самий zip.
#   tools/add-wlan-inject.sh <шлях до .ko>
# Значення прив'язки (ядро, збірка vendor, sha256 стокового драйвера) беруться з ПІДКЛЮЧЕНОГО по adb
# телефона: драйвер прив'язується саме до тієї прошивки, на якій його перевірено.
# Запускати ПЕРЕД tools/build-all.sh (або перепакуванням), щоб wlan/ потрапило у zip.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KO="${1:?usage: add-wlan-inject.sh <qca_cld3_wcn7750.ko>}"
W="$ROOT/module/nethunter-kmods/wlan"
[ -f "$KO" ] || { echo "no such file: $KO" >&2; exit 1; }

VFP="$(adb shell getprop ro.vendor.build.fingerprint | tr -d '\r')"
SSHA="$(adb shell "su -c 'sha256sum /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko'" | cut -d' ' -f1 | tr -d '\r')"
[ -n "$VFP" ] && [ "${#SSHA}" = 64 ] || { echo "could not read guard values from the phone (adb/root?)" >&2; exit 1; }

# драйвер мусить бути тієї ж версії qcacld, що й стоковий на телефоні — інакше це не паритетна збірка
# grep без -m1 і awk без раннього виходу читають потік до кінця, щоб pipefail не спрацьовував на SIGPIPE
ver_of() { grep -E '^5\.[0-9]+\.[0-9]+\.[0-9]+[A-Z]*$' | awk 'NR==1{v=$0} END{print v}'; }
STOCKVER="$(adb shell "su -c 'strings /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko'" | tr -d '\r' | ver_of)"
OURVER="$(strings "$KO" | ver_of)"
[ -n "$STOCKVER" ] && [ "$STOCKVER" = "$OURVER" ] || { echo "driver version '$OURVER' != stock '$STOCKVER'" >&2; exit 1; }

mkdir -p "$W"
cp "$KO" "$W/qca_cld3_wcn7750.ko"
echo "$VFP" > "$W/vendor.fingerprint"
echo "$SSHA" > "$W/stock.sha256"
echo "[+] staged into module/nethunter-kmods/wlan/"
echo "    driver:  qcacld $OURVER ($(stat -f%z "$KO" 2>/dev/null || stat -c%s "$KO") bytes)"
echo "    vendor:  $VFP"
echo "    stock:   $SSHA"
echo "    next: tools/build-all.sh (or repackage) -> one zip with the injection driver included"
