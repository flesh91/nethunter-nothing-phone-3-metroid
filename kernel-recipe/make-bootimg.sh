#!/bin/bash
# nethunter boot.img = the stock boot.img layout (header v4, empty ramdisk, empty cmdline)
# with our GKI Image, plus an AVB hash footer that copies every stock footer parameter.
#
#   docker run --rm -v nh-gki-out:/out -v "$PWD/kernel/tools":/t:ro \
#     -v "$PWD/fw/boot":/b:ro -v "$PWD/kernel-recipe":/r:ro nh-kbuild bash /r/make-bootimg.sh
#   /t : AOSP platform/system/tools/mkbootimg + platform/external/avb (git clone --depth 1)
# Output: /out/bootimg/nethunter-boot.img (+ .sha256)
#
# The image is signed with the AOSP test key, not Google's (which nobody outside Google has).
# On an UNLOCKED bootloader that is accepted with the orange-state warning, exactly like any
# custom or patched image. The ramdisk (and Magisk) live in init_boot, which stays untouched.
set -euo pipefail
STOCK=/b/boot.img IMG=/out/arch/arm64/boot/Image T=/t W=/out/bootimg
AVB=(python3 "$T/avb/avbtool.py")
[ -s "$IMG" ] || { echo "!! no $IMG — run build-gki.sh first"; exit 2; }
rm -rf "$W"; mkdir -p "$W"

python3 "$T/mkbootimg/unpack_bootimg.py" --boot_img "$STOCK" --out "$W/stock" >/dev/null
[ ! -s "$W/stock/ramdisk" ] || { echo "!! stock boot.img has a ramdisk — layout differs, stop"; exit 3; }

python3 "$T/mkbootimg/mkbootimg.py" --header_version 4 --kernel "$IMG" --cmdline '' \
    --output "$W/nethunter-boot.img"

# copy the stock footer parameters (rollback index, algorithm, props)
INFO="$("${AVB[@]}" info_image --image "$STOCK")"
PSIZE="$(stat -c %s "$STOCK")"
RBI="$(sed -n 's/^Rollback Index: *//p' <<<"$INFO")"
ALG="$(sed -n 's/^Algorithm: *//p' <<<"$INFO")"
PROPS=()
while IFS= read -r p; do PROPS+=(--prop "$p"); done < <(
  sed -n "s/^ *Prop: \(.*\) -> '\(.*\)'$/\1:\2/p" <<<"$INFO")
echo "stock footer: partition_size=$PSIZE rollback_index=$RBI algorithm=$ALG props=$(( ${#PROPS[@]} / 2 ))"

"${AVB[@]}" add_hash_footer --image "$W/nethunter-boot.img" --partition_name boot \
    --partition_size "$PSIZE" --algorithm "$ALG" --key "$T/avb/test/data/testkey_rsa4096.pem" \
    --rollback_index "$RBI" "${PROPS[@]}"

"${AVB[@]}" info_image --image "$W/nethunter-boot.img" | sed -n '1,4p;/Rollback Index:/p;/Algorithm:/p;/Prop:/p'
python3 "$T/mkbootimg/unpack_bootimg.py" --boot_img "$W/nethunter-boot.img" --out "$W/check" >/dev/null
cmp -s "$W/check/kernel" "$IMG" && echo "kernel inside image == our Image" || { echo "!! kernel mismatch"; exit 4; }
# grep the file directly: `strings | grep -m1` SIGPIPEs strings and pipefail+errexit aborts here
grep -a -m1 -o 'Linux version [[:print:]]*' "$W/check/kernel"
( cd "$W" && sha256sum nethunter-boot.img | tee nethunter-boot.img.sha256 )
