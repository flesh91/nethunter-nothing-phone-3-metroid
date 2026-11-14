#!/bin/bash
# NetHunter GKI kernel for Nothing Phone (3) "Metroid".
#
# Rebuilds the STOCK boot kernel — Google GKI 6.6.127-android15-8-gf0987337fa35-ab15756704-4k —
# from its exact ACK commit with the exact stock config (ikconfig from the stock boot.img),
# adds kernel-recipe/nethunter.config, and checks the result against the vmlinux.symvers Google
# published for that same build, so every stock vendor/GKI module keeps loading.
#
# Run inside the nh-kbuild image (arm64 Ubuntu, clang/lld 18, pahole 1.25):
#   docker run --rm -v nh-gki-src:/src -v nh-gki-out:/out \
#     -v "$PWD/kernel-recipe":/r:ro -v "$PWD/kernel/ref-ab15756704":/ref:ro \
#     nh-kbuild bash /r/build-gki.sh [config|build|check|all]
#   /src : ACK kernel/common @ f0987337fa35 on a CASE-SENSITIVE fs (a Docker volume, not macOS APFS)
#   /ref : stock.config + vmlinux.symvers + abi_symbollist.raw (ci.android.com build 15756704)
set -uo pipefail
ACK_SHA=f0987337fa351d7e303b071df533fd4c1c194687
# The release string must equal stock exactly: system_dlkm keeps its modules under
# /system_dlkm/lib/modules/<uname -r>/, so any other string means none of them are found.
# Kleaf builds it as  6.6.127 + <localversion file> + CONFIG_LOCALVERSION("-4k"),  with an
# empty scm part because it builds without .git. We do the same: a localversion file in O=
# and GIT_DIR pointed nowhere for make (scripts/setlocalversion then adds no -g<sha>/-dirty).
LOCALVER_FILE="-android15-8-gf0987337fa35-ab15756704"
WANT_REL="6.6.127${LOCALVER_FILE}-4k"
SRC=/src OUT=/out R=/r REF=/ref
LOG="$OUT/build-gki.log"
J="$(nproc)"
# Neutral, stable banner ("nethunter@metroid #1") instead of the container id.
MK=(env GIT_DIR=/nonexistent LOCALVERSION= KBUILD_BUILD_USER=nethunter KBUILD_BUILD_HOST=metroid
    KBUILD_BUILD_VERSION=1 make ARCH=arm64 LLVM=1 LLVM_IAS=1 O="$OUT")
STAGE="${1:-all}"
NEW_MODS="net/can/can-isotp.ko net/can/j1939/can-j1939.ko net/bluetooth/bnep/bnep.ko
drivers/net/usb/rndis_host.ko drivers/net/usb/qmi_wwan.ko drivers/net/usb/cdc_mbim.ko
drivers/usb/class/cdc-wdm.ko"

mkdir -p "$OUT"
say() { echo "== $*" | tee -a "$LOG"; }

check_src() {
  cd "$SRC" || exit 2
  [ "$(git rev-parse HEAD)" = "$ACK_SHA" ] || { echo "!! /src HEAD is not $ACK_SHA"; exit 2; }
  { [ -f net/netfilter/xt_DSCP.c ] && [ -f net/netfilter/xt_dscp.c ]; } || { echo "!! /src is not case-sensitive"; exit 2; }
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "!! /src has tracked changes"; exit 2; }
  ls localversion* >/dev/null 2>&1 && { echo "!! /src has localversion* files (would change the release string)"; exit 2; }
}

stage_config() {
  say "config: stock ikconfig (ab15756704) + nethunter.config + SIG_PROTECT off"
  # Google's export list for this build; the stock config names it relative to srctree.
  # + extra-exports.txt: vmlinux functions Google keeps unexported (TRIM_UNUSED_KSYMS) that USB Wi-Fi
  # modules from the module pipeline need. Only new exports: every stock symbol and CRC stay as-is.
  cp "$REF/abi_symbollist.raw" "$SRC/abi_symbollist.raw"
  [ -f "$R/extra-exports.txt" ] && grep -vE '^\s*(#|$)' "$R/extra-exports.txt" >> "$SRC/abi_symbollist.raw"
  printf '%s' "$LOCALVER_FILE" > "$OUT/localversion"
  cp "$REF/stock.config" "$OUT/.config"
  cat > "$OUT/nh-overrides.config" <<'EOF'
# Our kernel holds its own signing key, so Google-signed system_dlkm modules verify as
# -ENOKEY (unsigned). With SIG_PROTECT on they could not use GKI-protected symbols and
# Bluetooth/CAN/usbnet/zram would fail to load. Off, they load (kernel tainted 'E').
# Lockdown LSM is not built in this config, so unsigned modules are not otherwise blocked.
# CONFIG_MODULE_SIG_PROTECT is not set
EOF
  ./scripts/kconfig/merge_config.sh -m -O "$OUT" "$OUT/.config" \
      "$R/nethunter.config" "$OUT/nh-overrides.config" >>"$LOG" 2>&1 || { echo "!! merge failed"; exit 3; }
  "${MK[@]}" olddefconfig >>"$LOG" 2>&1 || { echo "!! olddefconfig failed"; tail -20 "$LOG"; exit 3; }
  python3 - "$REF/stock.config" "$OUT/.config" <<'PY' | tee -a "$LOG"
import re, sys
skip = re.compile(r'CONFIG_(CC_VERSION_TEXT|CLANG_VERSION|LLD_VERSION|AS_VERSION|LD_VERSION|RUSTC_VERSION|RUSTC_LLVM_VERSION|BINDGEN_VERSION_TEXT|GCC_VERSION)$')
def load(p):
    d = {}
    for l in open(p):
        l = l.strip()
        m = re.match(r'^(CONFIG_\w+)=(.*)$', l)
        if m: d[m.group(1)] = m.group(2); continue
        m = re.match(r'^# (CONFIG_\w+) is not set$', l)
        if m: d[m.group(1)] = 'n'
    return d
a, b = load(sys.argv[1]), load(sys.argv[2])
keys = sorted(k for k in set(a) | set(b) if not skip.match(k) and a.get(k, 'n') != b.get(k, 'n'))
print(f"config differences vs stock (toolchain version strings excluded): {len(keys)}")
for k in keys: print(f"  {k}: {a.get(k, '(absent)')} -> {b.get(k, '(absent)')}")
PY
  local rel; rel="$("${MK[@]}" -s kernelrelease 2>/dev/null)"
  echo "kernelrelease: $rel" | tee -a "$LOG"
  if [ "$rel" = "$WANT_REL" ]; then echo "release string: MATCHES stock" | tee -a "$LOG"
  else echo "!! release string differs from stock ($WANT_REL)" | tee -a "$LOG"; return 3; fi
}

stage_build() {
  say "build: Image + modules (-j$J)"
  local t0=$SECONDS
  "${MK[@]}" -j"$J" Image modules >>"$LOG" 2>&1; local rc=$?
  echo "make rc=$rc  ($(( (SECONDS - t0) / 60 )) min)" | tee -a "$LOG"
  [ $rc -eq 0 ] || { grep -nE " error:|Error [0-9]|No rule to make|ERROR:" "$LOG" | tail -25; exit 4; }
}

stage_check() {
  say "check: KMI vs Google's vmlinux.symvers for ab15756704"
  python3 "$R/kmi-check.py" "$REF/vmlinux.symvers" "$OUT/vmlinux.symvers" "$OUT/Module.symvers" | tee -a "$LOG"
  local kmi=${PIPESTATUS[0]}
  say "check: release string, Image, new modules"
  echo "kernel.release: $(cat "$OUT/include/config/kernel.release")" | tee -a "$LOG"
  strings "$OUT/arch/arm64/boot/Image" | grep -m1 "Linux version" | tee -a "$LOG"
  ls -la "$OUT/arch/arm64/boot/Image" | tee -a "$LOG"
  for m in $NEW_MODS; do
    if [ -f "$OUT/$m" ]; then
      printf "  %-34s %s\n" "$m" "$(strings "$OUT/$m" | grep -m1 '^vermagic=')" | tee -a "$LOG"
    else
      echo "  !! missing $m" | tee -a "$LOG"
    fi
  done
  return "$kmi"
}

check_src
case "$STAGE" in
  config) stage_config ;;
  build)  stage_build ;;
  check)  stage_check ;;
  all)    stage_config && stage_build && stage_check ;;
  *) echo "usage: build-gki.sh [config|build|check|all]"; exit 2 ;;
esac
