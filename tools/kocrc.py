#!/usr/bin/env python3
"""Витягує CRC експортів (__crc_*) та імпортів (__versions) з .ko (ELF64 LE)."""
import struct, sys

def load(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'\x7fELF' and b[4] == 2 and b[5] == 1, path
    shoff, = struct.unpack_from('<Q', b, 0x28)
    shentsize, shnum, shstrndx = struct.unpack_from('<HHH', b, 0x3a)
    secs = []
    for i in range(shnum):
        name, typ, flags, addr, off, size, link, info, align, entsize = struct.unpack_from('<IIQQQQIIQQ', b, shoff + i * shentsize)
        secs.append(dict(name=name, type=typ, off=off, size=size, link=link, entsize=entsize))
    strtab = secs[shstrndx]
    for s in secs:
        e = b.index(b'\0', strtab['off'] + s['name'])
        s['n'] = b[strtab['off'] + s['name']:e].decode()
    return b, secs

def exports(path):
    b, secs = load(path)
    out = {}
    for s in secs:
        if s['type'] != 2:  # SHT_SYMTAB
            continue
        st = secs[s['link']]
        for i in range(s['size'] // 24):
            nm, info, other, shndx, val, size = struct.unpack_from('<IBBHQQ', b, s['off'] + i * 24)
            e = b.index(b'\0', st['off'] + nm)
            name = b[st['off'] + nm:e].decode()
            if name.startswith('__crc_') and 0 < shndx < len(secs):
                sec = secs[shndx]
                out[name[6:]] = struct.unpack_from('<I', b, sec['off'] + val)[0]
    return out

def imports(path):
    b, secs = load(path)
    out = {}
    for s in secs:
        if s['n'] == '__versions':
            for i in range(s['size'] // 64):
                crc, = struct.unpack_from('<Q', b, s['off'] + i * 64)
                name = b[s['off'] + i * 64 + 8:s['off'] + i * 64 + 64].split(b'\0')[0].decode()
                out[name] = crc & 0xffffffff
    return out

if __name__ == '__main__':
    mode, *paths = sys.argv[1:]
    for p in paths:
        for k, v in sorted((exports if mode == 'exports' else imports)(p).items()):
            print(f'0x{v:08x}\t{k}\t{p.rsplit("/", 1)[-1]}')
