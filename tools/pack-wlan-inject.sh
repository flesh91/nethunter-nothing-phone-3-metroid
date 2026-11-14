#!/bin/bash
# Пакує Magisk-модуль nethunter-wlan-inject із зібраним драйвером qca_cld3_wcn7750.ko.
#   tools/pack-wlan-inject.sh <шлях до .ko> [версія, напр. v1]
# Значення запобіжника сумісності (ядро, збірка vendor, sha256 стокового драйвера) беруться
# з ПІДКЛЮЧЕНОГО по adb телефона: пакет прив'язується саме до тієї прошивки, на якій драйвер перевірено.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KO="${1:?usage: pack-wlan-inject.sh <qca_cld3_wcn7750.ko> [version]}"
VER="${2:-v1}"
M="$ROOT/module/nethunter-wlan-inject"
[ -f "$KO" ] || { echo "no such file: $KO" >&2; exit 1; }

KREL="$(adb shell uname -r | tr -d '\r')"
VFP="$(adb shell getprop ro.vendor.build.fingerprint | tr -d '\r')"
SSHA="$(adb shell "su -c 'sha256sum /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko'" | cut -d' ' -f1 | tr -d '\r')"
[ -n "$KREL" ] && [ -n "$VFP" ] && [ "${#SSHA}" = 64 ] || { echo "could not read guard values from the phone (adb/root?)" >&2; exit 1; }

# драйвер мусить бути тієї ж версії qcacld, що й стоковий на телефоні — інакше це не паритетна збірка
# grep без -m1 і awk без раннього виходу читають потік до кінця, щоб pipefail не спрацьовував на SIGPIPE
ver_of() { grep -E '^5\.[0-9]+\.[0-9]+\.[0-9]+[A-Z]*$' | awk 'NR==1{v=$0} END{print v}'; }
STOCKVER="$(adb shell "su -c 'strings /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko'" | tr -d '\r' | ver_of)"
OURVER="$(strings "$KO" | ver_of)"
[ -n "$STOCKVER" ] && [ "$STOCKVER" = "$OURVER" ] || { echo "driver version '$OURVER' != stock '$STOCKVER'" >&2; exit 1; }

STAGE="$(mktemp -d)"; trap 'rm -rf "$STAGE"' EXIT
cp -R "$M/." "$STAGE/"
cp "$KO" "$STAGE/qca_cld3_wcn7750.ko"
echo "$KREL" > "$STAGE/kernel.release"
echo "$VFP" > "$STAGE/vendor.fingerprint"
echo "$SSHA" > "$STAGE/stock.sha256"
VCODE="$(echo "$VER" | tr -cd '0-9')"; VCODE="${VCODE:-1}"
sed -i.bak -e "s/^version=.*/version=$VER/" -e "s/^versionCode=.*/versionCode=$VCODE/" "$STAGE/module.prop" && rm -f "$STAGE/module.prop.bak"

AB="$(echo "$KREL" | sed -n 's/.*-ab\([0-9]*\).*/\1/p')"
ZIP="$ROOT/out/nethunter-wlan-inject-metroid-ab${AB:-unknown}-$VER.zip"
mkdir -p "$ROOT/out"; rm -f "$ZIP"
(cd "$STAGE" && zip -qr9 "$ZIP" . -x '.*')
(cd "$ROOT/out" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
echo "[+] $ZIP"
echo "    driver:  qcacld $OURVER ($(stat -f%z "$KO" 2>/dev/null || stat -c%s "$KO") bytes)"
echo "    kernel:  $KREL"
echo "    vendor:  $VFP"
echo "    stock:   $SSHA"
