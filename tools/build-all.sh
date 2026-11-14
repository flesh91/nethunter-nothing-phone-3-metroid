#!/bin/bash
# Повна перезбірка NetHunter-модулів під стокове GKI-ядро Nothing Phone (3).
#
# Використання (після оновлення Nothing OS):
#   1. adb shell uname -r                → ab-номер збірки (напр. ab15756704) і коміт (g<sha>)
#   2. завантажити новий vendor_dlkm.img (nothing_archive) і розпакувати в fw/logical/vendor_dlkm
#   3. ./tools/build-all.sh <ab-номер> <повний sha коміту ACK>
#
# Що робить:
#   - бере артефакти Google CI саме цієї збірки ядра (Module.symvers, abi_symbollist, vmlinux)
#   - збирає ACK на тому самому коміті з конфігом телефону + nethunter-modules.fragment + patches/
#   - доводить, що KMI не змінився (CRC усіх символів = Google) і що CRC cfg80211/mac80211 = вендорські
#   - збирає out-of-tree (minstrel_ht, Realtek 8812au/8814au/8188eus)
#   - симулює правила завантаження GKI для кожного модуля і пакує zip для Magisk/KernelSU
set -euo pipefail
AB="${1:?kernel build ab number, e.g. 15756704}"; AB="${AB#ab}"
SHA="${2:?full kernel/common commit sha}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CI="https://ci.android.com/builds/submitted/$AB/kernel_aarch64/latest/raw"
cd "$ROOT"

echo "== 1. Google CI artifacts ($AB)"
mkdir -p stock dl/common build out
for f in kernel_aarch64_Module.symvers abi_symbollist.raw vmlinux gki-info.txt; do
  curl -fsSL -o "stock/ci_$f" "$CI/$f"
done
cat stock/ci_gki-info.txt
for f in kernel/module/gki_module.c android/abi_gki_protected_exports_aarch64; do
  curl -fsSL "https://android.googlesource.com/kernel/common/+/$SHA/$f?format=TEXT" | base64 -d > "stock/src_$(basename $f)"
done
[ -f "stock/device.config" ] || { echo "stock/device.config required: adb shell zcat /proc/config.gz > stock/device.config"; exit 1; }

echo "== 2. ACK sources $SHA"
TAR="dl/common/common-${SHA:0:12}.tar.gz"
[ -f "$TAR" ] || curl -fsSL -o "$TAR" "https://android.googlesource.com/kernel/common/+archive/$SHA.tar.gz"

echo "== 3. Vendor exports (vendor_dlkm)"
VD="fw/logical/vendor_dlkm/lib/modules"
[ -d "$VD" ] || { echo "$VD missing - extract vendor_dlkm.img (fsck.erofs --extract)"; exit 1; }
python3 -I tools/kocrc.py exports "$VD"/*.ko | awk -F'\t' '{m=$3; sub(/\.ko$/,"",m); printf "%s\t%s\tvendor/%s\tEXPORT_SYMBOL\t\n",$1,$2,m}' > build/vendor.symvers
python3 -I tools/kocrc.py exports "$VD"/cfg80211.ko "$VD"/mac80211.ko > build/vendor_wifi_exports.tsv
ls "$VD"/*.ko | xargs -n1 basename > build/vendor_ko.list
[ -d fw/logical/system_dlkm ] && find fw/logical/system_dlkm -name '*.ko' | xargs -n1 basename | sort > build/gki_ko.list

echo "== 4. Build in Docker (arm64, clang 18)"
docker build -q -t nh-kbuild docker >/dev/null
docker volume create nh-work >/dev/null
docker run --rm -v nh-work:/work -v "$ROOT":/h nh-kbuild bash -euc '
  rm -rf /work/common && mkdir -p /work/common && cd /work/common && tar xzf /h/'"$TAR"'
  for p in /h/patches/*.patch; do patch -p1 -s < "$p"; done
  cp /h/stock/device.config .config && cp /h/stock/ci_abi_symbollist.raw abi_symbollist.raw
  make ARCH=arm64 LLVM=1 olddefconfig >/dev/null 2>&1 && cp .config /work/base.config
  ./scripts/kconfig/merge_config.sh -m -O . .config /h/config/nethunter-modules.fragment >/dev/null 2>&1
  make ARCH=arm64 LLVM=1 olddefconfig >/dev/null 2>&1
  make -j"$(nproc)" ARCH=arm64 LLVM=1 LLVM_IAS=1 KBUILD_BUILD_USER=nh KBUILD_BUILD_HOST=nh Image modules > /work/build.log 2>&1 \
    || { grep -E " error:" /work/build.log | head; exit 1; }
  cp Module.symvers /h/build/nh_Module.symvers

  rm -rf /work/oot && cp -r /h/oot /work/oot
  cd /work/oot/rc80211_minstrel_ht && ./prepare.sh /work/common
  make -C /work/common ARCH=arm64 LLVM=1 LLVM_IAS=1 M=$PWD KBUILD_EXTRA_SYMBOLS=/h/build/vendor.symvers modules >/dev/null
  /work/oot/build-realtek.sh /work/common /h/build/vendor.symvers >/dev/null

  cd /work/common && rm -rf /work/stage && mkdir -p /work/stage/modules
  for p in $(cat modules.order); do k=${p%.o}.ko; b=$(basename $k)
    grep -qx "$b" /h/build/gki_ko.list && continue; grep -qx "$b" /h/build/vendor_ko.list && continue
    cp $k /work/stage/modules/; done
  cp /work/oot/rc80211_minstrel_ht/*.ko /work/oot/8812au-20210820/*.ko /work/oot/8814au/*.ko /work/oot/rtl8188eus/*.ko /work/stage/modules/
  for k in /work/stage/modules/*.ko; do llvm-strip --strip-debug $k; done
  # Модулі, яким потрібне власне ядро NetHunter (config/nh-kernel-only.list): окремо, їх кладе
  # в gki/ tools/add-gki-extras.sh; «!ім'\''я» — модуль дає саме ядро NetHunter, звідси не пакуємо.
  mkdir -p /work/stage/modules-nh
  grep -vE "^\s*(#|$)" /h/config/nh-kernel-only.list | while read -r n _; do
    case "$n" in
      !*) rm -f "/work/stage/modules/${n#!}.ko" ;;
      *)  mv "/work/stage/modules/$n.ko" /work/stage/modules-nh/ ;;
    esac
  done
  for k in /work/stage/modules/*.ko; do echo "$(basename $k .ko)|$(modinfo -F depends $k)|$(modinfo -F firmware $k | tr "\n" ",")"; done > /work/stage/modinfo.txt
  rm -rf /h/build/stage && cp -r /work/stage /h/build/stage
'

echo "== 5. Checks"
python3 -I - "$ROOT" <<'EOF'
import sys
root = sys.argv[1]
def load(p):
    d = {}
    for l in open(p):
        c, n, m, *_ = l.rstrip('\n').split('\t'); d[n] = (int(c, 16), m)
    return d
ci = load(f'{root}/stock/ci_kernel_aarch64_Module.symvers'); nh = load(f'{root}/build/nh_Module.symvers')
bad = [n for n in ci if n not in nh or nh[n][0] != ci[n][0]]
print(f'KMI: {len(ci)} Google symbols, mismatches {len(bad)}')
v = {}
for l in open(f'{root}/build/vendor_wifi_exports.tsv'):
    c, n, m = l.strip().split('\t'); v[n] = (int(c, 16), m)
wifi_bad = [n for n in v if n in nh and nh[n][1].endswith(('cfg80211', 'mac80211')) and nh[n][0] != v[n][0]]
print(f'cfg80211/mac80211 vs vendor: mismatches {len(wifi_bad)} {wifi_bad[:5]}')
if bad or wifi_bad: sys.exit(1)
EOF
python3 -I tools/check_gki_access.py "$ROOT" | tail -1 | tee /dev/stderr | grep -q "^\([0-9]*\)/\1 " || { echo "Some modules would fail to load"; exit 1; }

echo "== 6. Load order + packaging"
python3 -I - "$ROOT" <<'EOF'
import sys
root = sys.argv[1]
rows = [l.rstrip('\n').split('|') for l in open(f'{root}/build/stage/modinfo.txt')]
mods = {r[0]: [d for d in r[1].split(',') if d] for r in rows}
norm = lambda n: n.replace('-', '_')
order, seen = [], set()
def visit(m):
    if m in seen: return
    seen.add(m)
    for d in mods[m]:
        for x in mods:
            if norm(x) == norm(d): visit(x)
    order.append(m)
visit('rc80211_minstrel_ht')
# USB-пристрій бере драйвер, що зареєструвався першим. Порядок абеткою (out-of-tree 8188eu/8812au/8814au
# раніше за rtl8xxxu — TL-WN722N v2/v3 лишається за драйвером з injection), а rtl8192cu — в самому кінці:
# 60 його USB ID (RTL8188CUS/8192CU) знає й rtl8xxxu, і вони лишаються за rtl8xxxu, як було; ще 12 — лише він.
for m in sorted(mods, key=lambda m: (m == 'rtl8192cu', m)): visit(m)
open(f'{root}/build/stage/modules.order', 'w').write(''.join(f'{m}.ko\n' for m in order))
EOF
M=module/nethunter-kmods
rm -rf "$M/modules" && cp -r build/stage/modules "$M/modules" && cp build/stage/modules.order "$M/modules.order"
KREL="$(grep '^kernel_release=' stock/ci_gki-info.txt | cut -d= -f2)"
echo "$KREL" > "$M/kernel.release"
# Варіант B (власне ядро NetHunter, kernel-recipe/): оновити gki/ — функції ядра + модулі з
# config/nh-kernel-only.list; там же перевірка завантаження на цьому ядрі (tools/check_nh_kernel_access.py)
# лише якщо том зібраного ядра — саме під цю збірку (рецепт прив'язаний до свого ab; після OTA том
# лишається старим, і тоді модуль іде без gki/, а не падає вся збірка). docker volume inspect — першим:
# docker run -v мовчки створив би порожній том.
VOL="${NH_GKI_OUT:-nh-gki-out}"; VREL=""
docker volume inspect "$VOL" >/dev/null 2>&1 && \
  VREL="$(docker run --rm -v "$VOL":/out:ro nh-kbuild cat /out/include/config/kernel.release 2>/dev/null || true)"
# том за старою версією рецепта (до kernel-recipe/extra-exports.txt) має той самий kernel.release —
# тож ще й звіряємо, що всі додаткові експорти в ньому є
MISS=""
[ "$VREL" = "$KREL" ] && MISS="$(docker run --rm -v "$VOL":/out:ro -v "$ROOT/kernel-recipe":/r:ro nh-kbuild bash -c '
  cut -f2 /out/vmlinux.symvers /out/Module.symvers | sort -u > /tmp/have
  grep -vE "^\s*(#|$)" /r/extra-exports.txt | sort -u | comm -23 - /tmp/have | tr "\n" " "')"
if [ -d "kernel/ref-ab$AB/modules" ] && [ "$VREL" = "$KREL" ] && [ -z "$MISS" ]; then
  NH_REF="kernel/ref-ab$AB" ./tools/add-gki-extras.sh || { echo "NetHunter-kernel part (gki/) failed"; exit 1; }
else
  rm -rf "$M/gki"
  echo "No NetHunter kernel build for $KREL (volume $VOL: ${VREL:-none}; kernel/ref-ab$AB/modules: $([ -d kernel/ref-ab$AB/modules ] && echo yes || echo no)) - module ships without the gki/ part"
  [ -z "$MISS" ] || echo "  the kernel build predates kernel-recipe/extra-exports.txt (missing: $MISS) - rebuild it: kernel-recipe/build-gki.sh all"
  [ -z "$(ls build/stage/modules-nh 2>/dev/null)" ] || echo "  (skipped: $(ls build/stage/modules-nh | tr '\n' ' '))"
fi
ZIP="out/nethunter-kmods-metroid-ab$AB.zip"
rm -f "$ZIP" && (cd "$M" && zip -qr9 "$ROOT/$ZIP" . -x '.*')
shasum -a 256 "$ZIP"
