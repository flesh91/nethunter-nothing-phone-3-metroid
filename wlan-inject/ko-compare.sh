#!/bin/bash
# Статично порівнює зібраний qca_cld3_wcn7750.ko зі стоковим: версія, набори функцій та імпортів,
# CRC modversions і (необов'язково) паритетні макроси в рядку компіляції.
#   ko-compare.sh <stock.ko> <ours.ko> [<TAG>-hdd_main.cmd]
# stock.ko: adb pull /vendor_dlkm/lib/modules/qca_cld3_wcn7750.ko
# Потрібні llvm-nm, llvm-objcopy, llvm-strings (у PATH або в каталозі з $LLVM_BIN, напр. з Android NDK).
STOCK="${1:?usage: ko-compare.sh <stock.ko> <ours.ko> [hdd_main.cmd]}"
OURS="${2:?usage: ko-compare.sh <stock.ko> <ours.ko> [hdd_main.cmd]}"; CMD="${3:-}"
T="${LLVM_BIN:+$LLVM_BIN/}"
command -v "${T}llvm-nm" >/dev/null 2>&1 || { echo "llvm-nm not found (set LLVM_BIN)" >&2; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
size() { wc -c < "$1" | tr -d ' '; }
funcs(){ "${T}llvm-nm" --defined-only "$1" 2>/dev/null | awk '$2 ~ /^[tT]$/ {print $3}' | grep -vE '^__kcfi_typeid_|^\$|^__cfi_|\.cfi$' | sed -E 's/\.(llvm\.)?[0-9]+$//' | sort -u; }
imps(){ "${T}llvm-nm" -u "$1" 2>/dev/null | awk '{print $2}' | sort -u; }
for n in stock ours; do f=$STOCK; [ $n = ours ] && f=$OURS
  funcs "$f" > "$W/$n.f"; imps "$f" > "$W/$n.i"
  "${T}llvm-objcopy" --dump-section __versions="$W/$n.ver" "$f" /dev/null 2>/dev/null
  echo "$n: ver=$("${T}llvm-strings" "$f" | grep -E '^5\.[0-9]+\.[0-9]+\.[0-9]+[A-Z]*$' | head -1) size=$(size "$f") funcs=$(wc -l < "$W/$n.f" | tr -d ' ') imports=$(wc -l < "$W/$n.i" | tr -d ' ') $("${T}llvm-strings" "$f" | grep -m1 '^vermagic=')"
done
comm -23 "$W/stock.f" "$W/ours.f" > "$W/f.stock_only"; comm -13 "$W/stock.f" "$W/ours.f" > "$W/f.ours_only"
comm -23 "$W/stock.i" "$W/ours.i" > "$W/i.stock_only"; comm -13 "$W/stock.i" "$W/ours.i" > "$W/i.ours_only"
echo "functions only in STOCK: $(wc -l < "$W/f.stock_only" | tr -d ' ')   only in OURS: $(wc -l < "$W/f.ours_only" | tr -d ' ')"
echo "imports   only in STOCK: $(wc -l < "$W/i.stock_only" | tr -d ' ') [$(tr '\n' ' ' < "$W/i.stock_only")]   only in OURS: $(wc -l < "$W/i.ours_only" | tr -d ' ') [$(tr '\n' ' ' < "$W/i.ours_only")]"
echo "--- stock-only functions ---"; tr '\n' ' ' < "$W/f.stock_only"; echo
echo "--- ours-only functions (first 60) ---"; head -60 "$W/f.ours_only" | tr '\n' ' '; echo
python3 -I - "$W/stock.ver" "$W/ours.ver" <<'PY'
import sys
def load(p):
    b=open(p,'rb').read(); d={}
    for i in range(0,len(b),64):
        crc=int.from_bytes(b[i:i+8],'little'); name=b[i+8:i+64].split(b'\0')[0].decode()
        if name: d[name]=crc
    return d
s,o=load(sys.argv[1]),load(sys.argv[2])
common=set(s)&set(o); bad=[n for n in sorted(common) if s[n]!=o[n]]
print(f"CRC: stock={len(s)} ours={len(o)} common={len(common)} MISMATCH={len(bad)}")
for n in bad[:20]: print(f"   {n}: stock={s[n]:#010x} ours={o[n]:#010x}")
PY
if [ -n "$CMD" ] && [ -f "$CMD" ]; then
  echo "--- parity macros on the compile line ---"
  for m in ENABLE_CE4_COMP_DISABLE_HTT_HTC_MISC_LIST FEATURE_MGMT_RX_OVER_SRNG FEATURE_SMEM_MAILBOX WLAN_FEATURE_SSR_DRIVER_DUMP WLAN_CTRL_NAME WLAN_BCN_RATECODE_ENABLE WLAN_OPEN_SOURCE WLAN_TRACE_HIDE_MAC_ADDRESS QDF_NBUF_HISTORY_SIZE WLAN_MCC_MIN_CHANNEL_QUOTA WLAN_DISABLE_EXPORT_SYMBOL CONFIG_WLAN_SUPPORT_LAPB; do
    printf "  want   %-46s %s\n" "$m" "$(grep -q -- "-D$m\b" "$CMD" && echo OK || echo MISSING)"; done
  for m in DBR_MULTI_SRNG_ENABLE WLAN_DP_PROFILE_SUPPORT; do
    printf "  absent %-46s %s\n" "$m" "$(grep -q -- "-D$m\b" "$CMD" && echo PRESENT-BAD || echo OK)"; done
  printf "  info   %-46s %s\n" FEATURE_FRAME_INJECTION_SUPPORT "$(grep -q -- "-DFEATURE_FRAME_INJECTION_SUPPORT\b" "$CMD" && echo "present (injection build)" || echo "absent (base build)")"
fi
