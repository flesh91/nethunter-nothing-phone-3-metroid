#!/bin/bash
# Кладе в модуль (module/nethunter-kmods/gki/) усе, що потрібне лише власному ядру NetHunter (варіант B).
# Нічого не перелічено вручну — kernel-recipe/gki-stage.py виводить усе зі збірки:
#   - нові модулі: кожен .ko нашої збірки, якого немає серед гуглівських у system_dlkm;
#   - «батьківські»: гуглівські модулі, у копії яких Google вирізав експорт (TRIM_UNUSED_KSYMS), потрібний
#     новому модулю — їх беремо з нашої збірки й на телефоні вантажимо замість гуглівських (nh-gki);
#   - gki/load.order: порядок завантаження за полем depends кожного .ko;
#   - gki/kernel.version: точний /proc/version цієї збірки (за ним модуль упізнає саме це ядро);
#   - gki/boot.sha256: sha256 відповідного nethunter-boot.img (довідково).
#   tools/add-gki-extras.sh
# Потрібні: Docker-том nh-gki-out (kernel-recipe/build-gki.sh) і гуглівські модулі з телефона:
#   adb pull /system_dlkm/lib/modules/ kernel/ref-ab15756704/
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
G="$ROOT/module/nethunter-kmods/gki"
REF="$ROOT/kernel/ref-ab15756704"
VOL="${NH_GKI_OUT:-nh-gki-out}"
[ -d "$REF/modules" ] || { echo "!! no $REF/modules — run: adb pull /system_dlkm/lib/modules/ $REF/" >&2; exit 1; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

rm -rf "$G"; mkdir -p "$G"
docker run --rm -v "$VOL":/out:ro -v "$REF":/ref:ro -v "$ROOT/kernel-recipe":/r:ro -v "$G":/g -v "$TMP":/t nh-kbuild bash -c '
  set -e
  python3 /r/gki-stage.py /out /ref/modules /g
  cp /out/include/config/kernel.release /out/include/generated/compile.h /out/include/generated/utsversion.h /t/'

def() { sed -n "s/^#define $1[[:space:]]*\"\(.*\)\"$/\1/p" "$2"; }
REL="$(cat "$TMP/kernel.release")"
printf 'Linux version %s (%s@%s) (%s) %s\n' "$REL" \
  "$(def LINUX_COMPILE_BY "$TMP/compile.h")" "$(def LINUX_COMPILE_HOST "$TMP/compile.h")" \
  "$(def LINUX_COMPILER "$TMP/compile.h")" "$(def UTS_VERSION "$TMP/utsversion.h")" > "$G/kernel.version"
[ "$REL" = "$(cat "$ROOT/module/nethunter-kmods/kernel.release")" ] || {
  echo "!! this kernel build ($REL) is not the release the module targets" >&2; exit 1; }

BOOT="$ROOT/kernel/out-gki/nethunter-boot.img"
[ -f "$BOOT" ] && shasum -a 256 "$BOOT" | cut -d' ' -f1 > "$G/boot.sha256"

echo "[+] module/nethunter-kmods/gki/: $(ls "$G"/*.ko | wc -l | tr -d ' ') modules, load.order, kernel.version"
echo "    kernel: $(cat "$G/kernel.version")"
if adb get-state >/dev/null 2>&1; then
  if [ "$(adb shell cat /proc/version | tr -d '\r')" = "$(cat "$G/kernel.version")" ]; then
    echo "    phone : running THIS kernel build"
  else
    echo "    phone : running another kernel build — extras stay idle there until this boot.img runs"
  fi
fi
