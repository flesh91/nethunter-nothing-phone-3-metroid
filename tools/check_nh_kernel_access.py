#!/usr/bin/env python3
"""Чи завантажиться кожен модуль nethunter-kmods на ВЛАСНОМУ ядрі NetHunter (варіант B)?

Перевіряються: усе з gki/ (функції ядра + Wi-Fi з config/nh-kernel-only.list), стокова частина модуля
(build/stage/modules — на ядрі NetHunter вона теж вантажиться) і гуглівські модулі system_dlkm, що
імпортують щось у «батьківського» модуля, якого ми підміняємо нашою збіркою (cdc_ether ← usbnet тощо).

Те саме, що check_gki_access.py для стокового ядра, але правила нашого ядра:
  - експорти vmlinux — з vmlinux.symvers нашої збірки (KMI = Google + додаткові експорти);
  - MODULE_SIG_PROTECT вимкнено → правила «protected» немає;
  - «батьківські» модулі з gki/ (can, cdc_ncm, nfc) вантажаться ЗАМІСТЬ гуглівських,
    тож їхні експорти беруться з нашої копії, а не з гуглівської.
Символ шукається так само, як на телефоні: vmlinux → gki/ → модулі nethunter-kmods → vendor_dlkm →
гуглівські system_dlkm (реальні .ko з телефона, з урізаними TRIM_UNUSED_KSYMS експортами).
Перевіряються CRC (modversions), module_layout і дублікати експортів.

  check_nh_kernel_access.py <root> [<ref dir, типово kernel/ref-ab15756704>]
Перевіряє кінцевий стан (хто з ким зв'яжеться), а не перехід до нього: підміну батьківського модуля
на живому телефоні (зняття холдерів) виконує й журналює nh-gki.
Потрібні: kernel/out-gki/vmlinux.symvers, <ref dir>/modules/*.ko,
          build/vendor.symvers, build/stage/modules/*.ko, module/nethunter-kmods/gki/*.ko
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from kocrc import exports, imports  # noqa: E402

root = sys.argv[1]
ref = sys.argv[2] if len(sys.argv) > 2 else f'{root}/kernel/ref-ab15756704'
name = lambda p: os.path.basename(p)[:-3].replace('-', '_')


def symvers(p):
    d = {}
    for l in open(p):
        c, n, m, *_ = l.rstrip('\n').split('\t')
        d[n] = (int(c, 16), m)
    return d


vmlinux = {n: c for n, (c, m) in symvers(f'{root}/kernel/out-gki/vmlinux.symvers').items() if m == 'vmlinux'}
gki = sorted(glob.glob(f'{root}/module/nethunter-kmods/gki/*.ko'))
replaced = {name(p) for p in gki}            # наші копії стоять замість гуглівських з тим самим іменем

providers = []                               # (джерело, {символ: crc}) у порядку пошуку
providers.append(('gki', {}))
for p in gki:
    for n, c in exports(p).items():
        providers[0][1][n] = (c, name(p))
kmods = {}
for p in glob.glob(f'{root}/build/stage/modules/*.ko'):
    for n, c in exports(p).items():
        kmods[n] = (c, name(p))
providers.append(('nethunter-kmods', kmods))
providers.append(('vendor', {n: (c, m.split('/')[-1]) for n, (c, m) in symvers(f'{root}/build/vendor.symvers').items()}))
google = {}
for p in glob.glob(f'{ref}/modules/*.ko'):
    if name(p) in replaced:
        continue
    for n, c in exports(p).items():
        google[n] = (c, name(p))
providers.append(('google', google))

check = gki + sorted(glob.glob(f'{root}/build/stage/modules/*.ko'))
# гуглівські модулі, які на ядрі NetHunter прив'язуються до наших батьківських копій
parent_syms = {n for n, (c, m) in providers[0][1].items()}
for p in sorted(glob.glob(f'{ref}/modules/*.ko')):
    if name(p) not in replaced and parent_syms & set(imports(p)):
        check.append(p)

bad = 0
for p in check:
    probs = []
    for n, c in imports(p).items():
        if n == 'module_layout':
            if c != vmlinux.get(n):
                probs.append('module_layout CRC ≠ our vmlinux')
            continue
        if n in vmlinux:
            if vmlinux[n] != c:
                probs.append(f'{n}: CRC ≠ our vmlinux')
            continue
        for src, table in providers:
            if n in table:
                if table[n][0] != c:
                    probs.append(f'{n}: CRC ≠ {src}/{table[n][1]}')
                break
        else:
            probs.append(f'{n}: NOT EXPORTED on the NetHunter kernel')
    me = name(p)
    for n in exports(p):
        if n in vmlinux:
            probs.append(f'duplicate export {n} (vmlinux)')
        for src, table in providers:
            if n in table and table[n][1] != me:
                probs.append(f'duplicate export {n} ({src}/{table[n][1]})')
    if probs:
        bad += 1
        print(f'✗ {os.path.basename(p)}')
        for x in sorted(set(probs)):
            print('    ', x)
n_google = len(check) - len(gki) - len(glob.glob(f'{root}/build/stage/modules/*.ko'))
print(f'\n{len(check) - bad}/{len(check)} modules pass all checks on the NetHunter kernel '
      f'(gki/ {len(gki)}, stock part {len(check) - len(gki) - n_google}, Google modules bound to our parents {n_google})')
sys.exit(1 if bad else 0)
