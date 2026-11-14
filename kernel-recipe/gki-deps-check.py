#!/usr/bin/env python3
"""Will each extra module of the NetHunter kernel resolve its imports on the PHONE?

On the phone the extra modules link against: the vmlinux exports (= stock, KMI identical),
Google's real system_dlkm modules, and whatever we ship ourselves. Google builds its modules with
TRIM_UNUSED_KSYMS, so a Google module may simply not export what one of our extras needs
(can.ko lacks can_sock_destruct, cdc_ncm.ko exports nothing). This finds every such case
statically, from the actual Google .ko files pulled off the phone, instead of on the device.

  gki-deps-check.py <vmlinux.symvers> <google modules dir> <our Module.symvers> <our out dir> <ko>...
  (<ko> paths relative to <our out dir>; run where llvm-nm / llvm-objcopy exist, e.g. nh-kbuild)

Per import it reports: vmlinux | google:<mod> | shipped:<mod> (one of the given <ko>) |
NEED-OURS:<mod> (Google's copy lacks the export -> ship our build and load it instead) |
NEW-DEP:<mod> (not in system_dlkm at all -> ship it) | UNRESOLVED.
Prints the parents to ship and exits 1 if anything is UNRESOLVED.
"""
import glob
import os
import shutil
import struct
import subprocess
import sys
import tempfile

NM = shutil.which("llvm-nm-18") or shutil.which("llvm-nm")
OBJCOPY = shutil.which("llvm-objcopy-18") or shutil.which("llvm-objcopy")


def modname(path):
    return os.path.basename(path)[:-3].replace("-", "_")


def exports_of(ko):
    out = subprocess.run([NM, ko], capture_output=True, text=True).stdout
    return {l.split("__ksymtab_", 1)[1] for l in out.splitlines() if " __ksymtab_" in l}


def imports_of(ko):
    with tempfile.NamedTemporaryFile() as t:
        subprocess.run([OBJCOPY, f"--dump-section=__versions={t.name}", ko, "/dev/null"],
                       capture_output=True)
        d = open(t.name, "rb").read()
    names = []
    for i in range(0, len(d) - 63, 64):           # struct modversion_info { ulong crc; char name[56]; }
        n = d[i + 8:i + 64].split(b"\0")[0].decode()
        if n:
            names.append(n)
    return names


def symvers(path):
    m = {}
    for l in open(path):
        p = l.rstrip("\n").split("\t")
        if len(p) >= 3:
            m[p[1]] = p[2]
    return m


def main():
    if len(sys.argv) < 6:
        print(__doc__)
        return 2
    vmlinux = set(symvers(sys.argv[1]))
    gdir, ours_symvers, out = sys.argv[2], symvers(sys.argv[3]), sys.argv[4]
    kos = sys.argv[5:]
    google = {}                                    # symbol -> google module name
    gmods = set()
    for g in glob.glob(os.path.join(gdir, "*.ko")):
        gmods.add(modname(g))
        for s in exports_of(g):
            google[s] = modname(g)
    shipped = {modname(k) for k in kos}

    need_ours, new_dep, unresolved = {}, {}, {}
    for k in kos:
        res = {}
        for s in imports_of(os.path.join(out, k)):
            if s in vmlinux:
                res[s] = "vmlinux"
            elif s in google:
                res[s] = "google:" + google[s]
            elif s in ours_symvers and ours_symvers[s] != "vmlinux":
                prov = os.path.basename(ours_symvers[s]).replace("-", "_")
                if prov in shipped:
                    res[s] = "shipped:" + prov
                elif prov in gmods:
                    res[s] = "NEED-OURS:" + prov
                    need_ours.setdefault(prov, set()).add(s)
                else:
                    res[s] = "NEW-DEP:" + prov
                    new_dep.setdefault(prov, set()).add(s)
            else:
                res[s] = "UNRESOLVED"
                unresolved.setdefault(modname(k), set()).add(s)
        kinds = {}
        for v in res.values():
            kinds[v.split(":")[0]] = kinds.get(v.split(":")[0], 0) + 1
        bad = {s: v for s, v in res.items() if v.split(":")[0] in ("NEED-OURS", "NEW-DEP", "UNRESOLVED")}
        print(f"{modname(k):14} imports={len(res):3}  " + "  ".join(f"{a}={b}" for a, b in sorted(kinds.items())))
        for s, v in sorted(bad.items()):
            print(f"    {v:28} {s}")

    print()
    for p, syms in sorted(need_ours.items()):
        print(f"SHIP OUR {p}.ko instead of Google's (missing exports: {', '.join(sorted(syms))})")
    for p, syms in sorted(new_dep.items()):
        print(f"SHIP {p}.ko too (not in system_dlkm; needed for: {', '.join(sorted(syms))})")
    for m, syms in sorted(unresolved.items()):
        print(f"UNRESOLVED in {m}: {', '.join(sorted(syms))}")
    print("DEPS:", "OK" if not unresolved else "UNRESOLVED")
    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
