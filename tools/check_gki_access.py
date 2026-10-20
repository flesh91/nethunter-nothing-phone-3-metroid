#!/usr/bin/env python3
"""Перевіряє, що кожен модуль завантажиться на стоковому GKI-ядрі:
симулює resolve_symbol() з kernel/module/main.c (ANDROID GKI) + перевірку CRC (modversions)
та verify_exported_symbols() (protected exports, дублікати)."""
import os, sys
sys.path.insert(0, os.path.dirname(__file__))
from kocrc import imports, exports

root = sys.argv[1]
def symvers(p):
    d = {}
    for l in open(p):
        c, n, m, *_ = l.rstrip('\n').split('\t'); d[n] = (int(c, 16), m)
    return d
ci = symvers(f'{root}/stock/ci_kernel_aarch64_Module.symvers')          # vmlinux + GKI-модулі (підписані Google)
vendor = symvers(f'{root}/build/vendor.symvers')                        # vendor_dlkm (непідписані)
unprot = set(open(f'{root}/stock/ci_abi_symbollist.raw').read().split())  # gki_module_unprotected
protected_exports = set(open(f'{root}/stock/src_abi_gki_protected_exports_aarch64').read().split())

mods = sorted(f for f in os.listdir(f'{root}/build/stage/modules') if f.endswith('.ko'))
ours = {}
for m in mods:
    for n, c in exports(f'{root}/build/stage/modules/{m}').items():
        ours[n] = (c, m)

bad = 0
for m in mods:
    path = f'{root}/build/stage/modules/{m}'
    probs = []
    for n, c in imports(path).items():
        if n == 'module_layout':
            if c != ci.get(n, (None,))[0]: probs.append(f'module_layout CRC')
            continue
        if n in ours:
            if ours[n][0] != c: probs.append(f'{n}: CRC ≠ {ours[n][1]}')
        elif n in vendor:
            if vendor[n][0] != c: probs.append(f'{n}: CRC ≠ vendor/{vendor[n][1]}')
        elif n in ci:
            if n not in unprot: probs.append(f'{n}: PROTECTED ({ci[n][1]})')
            elif ci[n][0] != c: probs.append(f'{n}: CRC ≠ GKI')
        else:
            probs.append(f'{n}: NOT EXPORTED on the phone')
    for n in exports(path):
        if n in protected_exports: probs.append(f'exports protected {n}')
        if n in ci or n in vendor: probs.append(f'duplicate export {n}')
    if probs:
        bad += 1
        print(f'✗ {m}'); [print('    ', p) for p in sorted(set(probs))]
print(f'\n{len(mods) - bad}/{len(mods)} modules pass all checks')
