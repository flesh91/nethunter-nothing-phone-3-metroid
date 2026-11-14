#!/usr/bin/env python3
"""KMI check: our rebuilt GKI vs Google's own build of the stock kernel.

Compares the vmlinux export table (symbol -> CRC) of our build against the
vmlinux.symvers Google published for the stock build (ci.android.com, ab15756704).
Every symbol the stock kernel exports must be present in ours with the SAME CRC,
otherwise a stock vendor/GKI module that imports it will refuse to load.
Extra exports on our side are harmless (nothing stock imports them).

  kmi-check.py <ref vmlinux.symvers> <our vmlinux.symvers> [<our Module.symvers>]
Exit: 0 = KMI identical, 1 = missing/mismatched symbols, 2 = usage/IO error.
"""
import sys


def load(path):
    """symvers line: 0xCRC<TAB>symbol<TAB>module<TAB>EXPORT_TYPE[<TAB>namespace]"""
    out = {}
    with open(path) as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 3:
                continue
            crc, sym, mod = p[0], p[1], p[2]
            out[sym] = (crc.lower(), mod, p[3] if len(p) > 3 else "")
    return out


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    ref = load(sys.argv[1])
    ours = load(sys.argv[2])
    if len(sys.argv) > 3:          # fall back to Module.symvers' vmlinux rows
        for s, v in load(sys.argv[3]).items():
            if v[1] == "vmlinux":
                ours.setdefault(s, v)

    missing = sorted(s for s in ref if s not in ours)
    mismatch = sorted(s for s in ref if s in ours and ref[s][0] != ours[s][0])
    typediff = sorted(s for s in ref if s in ours and ref[s][2] != ours[s][2])
    extra = sorted(s for s in ours if s not in ref and ours[s][1] == "vmlinux")

    print(f"stock exports : {len(ref)}")
    print(f"ours (vmlinux): {sum(1 for v in ours.values() if v[1] == 'vmlinux')}")
    print(f"missing in ours        : {len(missing)}")
    print(f"CRC mismatch           : {len(mismatch)}")
    print(f"export-type differs    : {len(typediff)}")
    print(f"extra exports in ours  : {len(extra)}  (harmless)")
    for title, lst in (("MISSING", missing), ("CRC MISMATCH", mismatch), ("TYPE DIFF", typediff)):
        for s in lst[:40]:
            r, o = ref[s], ours.get(s)
            print(f"  {title:12} {s:48} stock={r[0]} ours={o[0] if o else '-'}")
        if len(lst) > 40:
            print(f"  ... {len(lst) - 40} more {title}")
    if extra:
        print("  extra (first 15): " + ", ".join(extra[:15]))
    ok = not missing and not mismatch
    print("KMI: IDENTICAL" if ok else "KMI: BROKEN")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
