#!/usr/bin/env python3
"""Stage the NetHunter-kernel extras for the module's gki/ dir — fully derived, no hand lists.

  gki-stage.py <our out dir> <Google system_dlkm modules dir> <dest gki dir>
  (run inside nh-kbuild: needs llvm-nm / llvm-objcopy; uses gki-deps-check.py next to it)

- new modules : every .ko of our build whose file name is not among Google's system_dlkm modules
- parents     : Google modules whose copy lacks an export a new module needs (TRIM_UNUSED_KSYMS)
                -> our build of them is shipped and loaded instead
- load order  : topological over each module's .modinfo "depends" (shipped modules only)
Writes <dest>/*.ko and <dest>/load.order, one line per module:
    <file without .ko> <kind> <depends csv or ->
    kind = new | parent:<a symbol only our build exports>   (used on the phone to tell ours from Google's)
Exits 1 if any new module would not resolve on the phone.
"""
import glob
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("deps", os.path.join(HERE, "gki-deps-check.py"))
deps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deps)


def norm(n):
    return n.replace("-", "_")


def modinfo_depends(ko):
    with tempfile.NamedTemporaryFile() as t:
        subprocess.run([deps.OBJCOPY, f"--dump-section=.modinfo={t.name}", ko, "/dev/null"], capture_output=True)
        for kv in open(t.name, "rb").read().split(b"\0"):
            if kv.startswith(b"depends="):
                v = kv[len(b"depends="):].decode()
                return [norm(d) for d in v.split(",") if d]
    return []


def main():
    out, gdir, dest = sys.argv[1:4]
    goog = {os.path.basename(g) for g in glob.glob(os.path.join(gdir, "*.ko"))}
    ours = sorted(os.path.relpath(p, out) for p in glob.glob(os.path.join(out, "**", "*.ko"), recursive=True))
    new = [p for p in ours if os.path.basename(p) not in goog]
    by_name = {norm(os.path.basename(p)[:-3]): p for p in ours}

    vmlinux = set(deps.symvers(os.path.join(out, "vmlinux.symvers")))
    gexp, gmods = {}, set()
    for g in glob.glob(os.path.join(gdir, "*.ko")):
        gmods.add(deps.modname(g))
        for s in deps.exports_of(g):
            gexp[s] = deps.modname(g)
    oexp = deps.symvers(os.path.join(out, "Module.symvers"))
    shipped = {deps.modname(p) for p in new}

    parents, unresolved = {}, []
    for p in new:
        for s in deps.imports_of(os.path.join(out, p)):
            if s in vmlinux or s in gexp:
                continue
            prov = norm(os.path.basename(oexp.get(s, "")))
            if not prov or oexp.get(s) == "vmlinux":
                unresolved.append(f"{deps.modname(p)}:{s}")
            elif prov in shipped:
                continue
            elif prov in gmods:
                parents.setdefault(prov, s)
            else:                                   # a dependency Google does not ship at all
                new.append(by_name[prov]); shipped.add(prov)
    if unresolved:
        print("UNRESOLVED:", ", ".join(unresolved)); return 1

    ship = {deps.modname(p): p for p in new}
    for prov in parents:
        ship[prov] = by_name[prov]
    dep = {n: modinfo_depends(os.path.join(out, p)) for n, p in ship.items()}

    order, done = [], set()
    def visit(n, stack=()):
        if n in done:
            return
        if n in stack:
            raise SystemExit(f"dependency cycle at {n}")
        for d in dep[n]:
            if d in ship:
                visit(d, stack + (n,))
        done.add(n); order.append(n)
    for n in sorted(ship, key=lambda n: (n not in parents, n)):
        visit(n)

    os.makedirs(dest, exist_ok=True)
    with open(os.path.join(dest, "load.order"), "w") as f:
        for n in order:
            p = ship[n]
            shutil.copy2(os.path.join(out, p), dest)
            kind = f"parent:{parents[n]}" if n in parents else "new"
            f.write(f"{os.path.basename(p)[:-3]} {kind} {','.join(dep[n]) or '-'}\n")
    print(f"staged {len(order)} modules: {len(order) - len(parents)} new + parents {', '.join(sorted(parents)) or 'none'}")
    for n in order:
        print("  " + n + ("  (parent)" if n in parents else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
