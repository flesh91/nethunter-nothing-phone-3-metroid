#!/bin/bash
# Готує дерево драйвера Wi-Fi для збірки: чиста копія WLAN-джерел із дерева ядра Nothing +
# дельта апстріму до версії стокового бінарника (5.2.1.123K) + паритет зі стоковою збіркою + патчі.
#   wlan-inject/prepare-tree.sh <дерево ядра NothingOSS sm8735 (git)> <порожня тека-результат> [--base]
# --base : зупинитись після паритету (драйвер без інжекції, еквівалент стокового — для перевірки збірки).
# Результат: <тека>/vendor/qcom/opensource/wlan — монтується в контейнер як /parity (див. build-driver.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
KSRC="${1:?usage: prepare-tree.sh <kernel tree> <out dir> [--base]}"
OUT="${2:?usage: prepare-tree.sh <kernel tree> <out dir> [--base]}"
MODE="${3:-}"
P="$HERE/patches"

[ -d "$KSRC/.git" ] || { echo "not a git checkout: $KSRC" >&2; exit 1; }
mkdir -p "$OUT"
[ -z "$(ls -A "$OUT")" ] || { echo "output dir is not empty: $OUT" >&2; exit 1; }

# 1. чиста копія з HEAD (без локальних змін і артефактів збірки)
git -C "$KSRC" archive HEAD vendor/qcom/opensource/wlan | tar -x -C "$OUT"
W="$OUT/vendor/qcom/opensource/wlan"
ver() { grep -E 'define QWLAN_VERSIONSTR ' "$W/qcacld-3.0/core/mac/inc/qwlan_version.h" | awk '{print $3}' | tr -d '"'; }
[ "$(ver)" = "5.2.1.123" ] || { echo "expected qcacld 5.2.1.123 in $KSRC, found $(ver)" >&2; exit 1; }

apply() { # $1=каталог усередині wlan, $2=патч
  (cd "$W/$1" && patch -p1 -s --dry-run < "$2" >/dev/null && patch -p1 -s < "$2") || { echo "patch failed: $2" >&2; exit 1; }
  echo "  applied $(basename "$2")"
}

# 2. дельта апстріму Qualcomm (CodeLinaro) до версії стокового бінарника 5.2.1.123K
echo "== upstream delta 5.2.1.123 -> 5.2.1.123K"
apply qcacld-3.0 "$P/k-delta/qcacld-3.0-123-to-123K.patch"
apply qca-wifi-host-cmn "$P/k-delta/qca-wifi-host-cmn-to-123K.patch"
apply fw-api "$P/k-delta/fw-api-to-123K.patch"
# єдиний ханк, вилучений із дельти qcacld: Nothing дописала в кінець defconfig власний рядок
DC="$W/qcacld-3.0/configs/sun_gki_wcn7750_defconfig"
grep -q '^CONFIG_WLAN_CHIPSET_LOG_MAX_SIZE=y$' "$DC" || { echo "defconfig anchor missing" >&2; exit 1; }
perl -0pi -e 's/^(CONFIG_WLAN_CHIPSET_LOG_MAX_SIZE=y\n)/$1CONFIG_FEATURE_WLAN_ZERO_POWER_SCAN=y\n/m' "$DC"
grep -q '^CONFIG_FEATURE_WLAN_ZERO_POWER_SCAN=y$' "$DC"
[ "$(ver)" = "5.2.1.123K" ] || { echo "version after delta: $(ver)" >&2; exit 1; }

# 3. паритет набору макросів зі стоковою (Bazel/DDK) збіркою
echo "== stock parity"
python3 "$HERE/parity-apply.py" "$W/qcacld-3.0"

if [ "$MODE" = "--base" ]; then echo "base tree ready (no injection): $W"; exit 0; fi

# 4. монітор та інжекція
echo "== monitor mode and injection"
for p in "$P"/0*.patch; do apply . "$p"; done
find "$W" \( -name '*.orig' -o -name '*.rej' \) -delete
echo "tree ready: $W  (qcacld $(ver))"
