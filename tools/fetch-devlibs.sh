#!/bin/sh
# Витягує з підключеного по adb пристрою системні бібліотеки, потрібні лише для ЛІНКУВАННЯ
# nh-btbridge (їх ми не зберігаємо в репозиторії — вони пропрієтарні). Потрібен root (su) на пристрої.
set -e
OUT="$(cd "$(dirname "$0")/.." && pwd)/btbridge/devlibs"
mkdir -p "$OUT"
for l in libbinder_ndk.so libc.so liblog.so libdl.so libm.so; do
  adb pull "/system/lib64/$l" "$OUT/$l" >/dev/null && echo "pulled $l"
done
