#!/bin/sh
# Збірка nh-btbridge (bionic/arm64) у контейнері nh-kbuild. $1 = корінь NDK
set -e
NDK="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"
SYSROOT="$NDK/toolchains/llvm/prebuilt/linux-x86_64/sysroot"
BUILTINS="$(ls "$NDK"/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/*/lib/linux/libclang_rt.builtins-aarch64-android.a)"
clang --target=aarch64-linux-android31 --sysroot="$SYSROOT" -fuse-ld=lld \
  -O2 -Wall -Wextra -Wno-unused-parameter -fPIE -pie -fstack-protector-strong \
  -o "$HERE/nh-btbridge" "$HERE/nh-btbridge.c" \
  -nodefaultlibs -L"$HERE/devlibs" -lbinder_ndk -lc -ldl "$BUILTINS"
llvm-strip "$HERE/nh-btbridge"
file "$HERE/nh-btbridge"
