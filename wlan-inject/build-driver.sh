#!/bin/bash
# Збирає qca_cld3_wcn7750.ko як зовнішній модуль (усередині контейнера збірки) з дерева,
# підготовленого prepare-tree.sh, проти виходу kernel-prep.sh.
#
#   docker run --rm -e TAG=<ім'я> \
#     -v <дерево ядра>:/src -v <вихід prepare-tree.sh>:/parity \
#     -v nh-work:/work -v <цей каталог wlan-inject>:/h <образ> bash /h/build-driver.sh
#
# Результат у /h: qca_cld3_wcn7750.$TAG.ko, $TAG-hdd_main.cmd (рядок компіляції для ko-compare.sh),
# qcacld-$TAG.log. Повна збірка ~35 хв; після правки одного файла — менше хвилини.
set -o pipefail
: "${TAG:?set TAG}"
SRC=/src; OUT=/work/fullout-cs; LOG=/work/qcacld-$TAG.log
WL=/parity/vendor/qcom/opensource/wlan; Q="$WL/qcacld-3.0"
PLATSYM=/src/vendor/qcom/opensource/wlan/platform/Module.symvers
# Єдиний імпорт стокового драйвера, якого немає у symvers власної збірки платформних модулів
# (FEATURE_SMEM_MAILBOX): CRC взято з таблиці __versions стокового .ko.
EXTRA=/h/parity-extra.symvers
UTS="${UTS_RELEASE:-6.6.127-android15-8-maybe-dirty-4k}"
: > "$LOG"; cd "$SRC" || exit 2
A=(ARCH=arm64 LLVM=1 LLVM_IAS=1); J="$(nproc)"
echo "#define UTS_RELEASE \"$UTS\"" > "$OUT/include/generated/utsrelease.h"
echo "== build $TAG ($(date +%H:%M:%S)) ==" | tee -a "$LOG"
make -C "$SRC" O="$OUT" M="$Q" modules -j"$J" "${A[@]}" \
  WLAN_ROOT="$Q" WLAN_PROFILE=sun_gki_wcn7750 MODNAME=qca_cld3_wcn7750 CHIP_NAME=wcn7750 DEVNAME=wcn7750 \
  WLAN_CTRL_NAME=wlan \
  CONFIG_QCA_CLD_WLAN=m CONFIG_QCA_WIFI_ISOC=0 CONFIG_QCA_WIFI_2_0=1 QCA_WIFI_FTM_NL80211=y \
  KBUILD_EXTRA_SYMBOLS="$PLATSYM $EXTRA" \
  KCFLAGS="-Wno-error -Wno-unknown-warning-option -D__ANDROID_COMMON_KERNEL__ -DCONFIG_NL80211_TESTMODE=1" \
  >>"$LOG" 2>&1
RC=$?
echo "make rc=$RC ($(date +%H:%M:%S))" | tee -a "$LOG"
grep -E "undefined!|exported twice| error:|No rule to make" "$LOG" | sort -u | tail -20
if [ $RC -ne 0 ]; then echo "!! BUILD FAILED ($TAG)"; tail -25 "$LOG"; cp "$LOG" "/h/qcacld-$TAG.log"; exit $RC; fi
K="$Q/qca_cld3_wcn7750.ko"
cp "$Q/core/hdd/src/.wlan_hdd_main.o.cmd" "/h/$TAG-hdd_main.cmd" 2>/dev/null
llvm-strip --strip-debug "$K"
echo "vermagic: $(modinfo -F vermagic "$K")  size=$(stat -c%s "$K")" | tee -a "$LOG"
cp "$K" "/h/qca_cld3_wcn7750.$TAG.ko" && echo "copied -> qca_cld3_wcn7750.$TAG.ko" | tee -a "$LOG"
cp "$LOG" "/h/qcacld-$TAG.log"
echo "DONE $TAG"
