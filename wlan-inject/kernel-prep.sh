#!/bin/bash
# Одноразова підготовка (усередині контейнера збірки): ПОВНА збірка вендорського ядра Nothing,
# щоб отримати узгоджений Module.symvers, і збірка платформних WLAN-модулів (cnss_*) заради
# їхніх експортів. Саме ядро на телефон НЕ ставиться — потрібні лише заголовки, конфіг і symvers.
#
#   docker run --rm -v <дерево ядра>:/src -v nh-work:/work -v <цей каталог wlan-inject>:/h <образ> bash /h/kernel-prep.sh
#   (образ: docker/Dockerfile цього репозиторію; дерево ядра мусить лежати на РЕГІСТРОЗАЛЕЖНІЙ
#    файловій системі — у ядрі є файли xt_DSCP.c і xt_dscp.c; на macOS це окремий APFS-том)
#
# Результат: /work/fullout-cs (O= каталог ядра) і /src/vendor/qcom/opensource/wlan/platform/Module.symvers.
# Триває години. Повторювати лише після зміни ядра (оновлення Nothing OS + новий дроп джерел).
set -o pipefail
SRC=/src
OUT=/work/fullout-cs
LOG=/work/full-build-cs.log
WL="$SRC/vendor/qcom/opensource/wlan"
# Має збігатися з vermagic стокових вендор-модулів: modinfo -F vermagic /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko
UTS="${UTS_RELEASE:-6.6.127-android15-8-maybe-dirty-4k}"
: > "$LOG"; mkdir -p "$OUT"; cd "$SRC" || exit 2
A=(ARCH=arm64 LLVM=1 LLVM_IAS=1)
J="$(nproc)"

echo "== [0] case-sensitive source?" | tee -a "$LOG"
if [ -f "$SRC/net/netfilter/xt_DSCP.c" ] && [ -f "$SRC/net/netfilter/xt_dscp.c" ]; then
  echo "  ok" | tee -a "$LOG"
else
  echo "  !! xt_DSCP.c / xt_dscp.c collide: the source is on a case-insensitive filesystem" | tee -a "$LOG"; exit 9
fi

echo "== [1] configure: gki_defconfig + vendor/sun_perf.config + vendor/Metroid.config" | tee -a "$LOG"
make O="$OUT" "${A[@]}" gki_defconfig >>"$LOG" 2>&1 || { echo "gki_defconfig FAILED"; tail -20 "$LOG"; exit 3; }
./scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
   arch/arm64/configs/vendor/sun_perf.config arch/arm64/configs/vendor/Metroid.config >>"$LOG" 2>&1 || { echo "merge FAILED"; exit 3; }
make O="$OUT" "${A[@]}" olddefconfig >>"$LOG" 2>&1 || { echo "olddefconfig FAILED"; exit 3; }

echo "== [2] full build: Image + modules" | tee -a "$LOG"
make O="$OUT" "${A[@]}" -j"$J" Image modules >>"$LOG" 2>&1
echo "  make rc=$?  Module.symvers lines: $(wc -l < "$OUT/Module.symvers" 2>/dev/null)" | tee -a "$LOG"
[ -s "$OUT/Module.symvers" ] || { echo "!! no Module.symvers"; grep -E " error:|Error |No rule" "$LOG" | tail -25; exit 5; }

echo "== [3] pin UTS_RELEASE to the stock vendor-module vermagic" | tee -a "$LOG"
echo "#define UTS_RELEASE \"$UTS\"" > "$OUT/include/generated/utsrelease.h"

echo "== [4] WLAN platform modules (cnss_utils / cnss_nl / icnss2 ...) -> platform/Module.symvers" | tee -a "$LOG"
# qcacld імпортує cnss_utils_*, cld80211_*, register_cld_cmd_cb з цих сусідніх модулів;
# 'make Image modules' їх не збирає.
PLAT="$WL/platform"
make -C "$PLAT" KERNEL_SRC="$OUT" M="$PLAT" "${A[@]}" modules -j"$J" \
  KCFLAGS="-Wno-error -Wno-unknown-warning-option -Wno-missing-prototypes" >>"$LOG" 2>&1
echo "  make rc=$?  symvers lines: $(wc -l < "$PLAT/Module.symvers" 2>/dev/null)" | tee -a "$LOG"
[ -s "$PLAT/Module.symvers" ] || { echo "!! platform produced no Module.symvers"; grep -E ' error:' "$LOG" | tail -15; exit 6; }
echo "DONE: $OUT and $PLAT/Module.symvers"
