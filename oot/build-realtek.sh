#!/bin/bash
# Збирає out-of-tree Realtek-драйвери проти дерева ядра. $1=дерево ядра, $2=vendor.symvers
set -e
K="$1"; SYMS="$2"; HERE="$(cd "$(dirname "$0")" && pwd)"
for d in 8812au-20210820 8814au rtl8188eus; do
  cd "$HERE/$d"
  cp "$HERE/nh_compat.c" .
  grep -q nh_compat Makefile || printf '\n# NetHunter/GKI: заглушки файлових API\n$(MODULE_NAME)-y += nh_compat.o\n' >> Makefile
  v=$(grep -oE "^export CONFIG_RTL[0-9A-Z]+ = m" Makefile | head -1 | awk '{print $2}')
  make -C "$K" ARCH=arm64 LLVM=1 LLVM_IAS=1 M="$PWD" "$v=m" \
    KCFLAGS="-Wno-error -Wno-unknown-warning-option -Wno-error=incompatible-pointer-types-discards-qualifiers -Wno-error=incompatible-pointer-types" \
    KBUILD_EXTRA_SYMBOLS="$SYMS" modules -j8 > build.log 2>&1 || { echo "FAIL $d"; grep -E "error:|ERROR:" build.log | head -5; continue; }
  ls -la *.ko
done
