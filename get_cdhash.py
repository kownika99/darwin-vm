#!/usr/bin/env python3
"""
Extract CDHash (SHA1 of CodeDirectory) from a Mach-O binary.
Prints the 40-char hex CDHash to stdout, or nothing on failure.
Used as a Linux replacement for: codesign -d -vvv <binary> | grep CDHash
"""
import sys
import struct
import hashlib

MH_MAGIC_64    = 0xFEEDFACF
MH_CIGAM_64    = 0xCFFAEDFE
FAT_MAGIC      = 0xCAFEBABE
FAT_CIGAM      = 0xBEBAFECA

LC_CODE_SIGNATURE = 0x1D

CS_MAGIC_EMBEDDED_SIGNATURE = 0xFADE0CC0
CS_MAGIC_CODEDIRECTORY      = 0xFADE0C02
CSSLOT_CODEDIRECTORY        = 0


def _cdhash_from_sig(sig: bytes) -> str | None:
    if len(sig) < 12:
        return None
    magic, _length, count = struct.unpack('>III', sig[:12])
    if magic != CS_MAGIC_EMBEDDED_SIGNATURE:
        return None
    for i in range(count):
        off = 12 + i * 8
        if off + 8 > len(sig):
            break
        blob_type, blob_offset = struct.unpack('>II', sig[off:off + 8])
        if blob_type != CSSLOT_CODEDIRECTORY:
            continue
        if blob_offset + 8 > len(sig):
            break
        cd_magic = struct.unpack('>I', sig[blob_offset:blob_offset + 4])[0]
        if cd_magic != CS_MAGIC_CODEDIRECTORY:
            continue
        cd_len = struct.unpack('>I', sig[blob_offset + 4:blob_offset + 8])[0]
        cd_data = sig[blob_offset:blob_offset + cd_len]
        return hashlib.sha1(cd_data).hexdigest()
    return None


def _cdhash_from_macho(data: bytes) -> str | None:
    if len(data) < 4:
        return None
    magic = struct.unpack('<I', data[:4])[0]
    if magic == MH_MAGIC_64:
        fmt = '<'
    elif magic == MH_CIGAM_64:
        fmt = '>'
    else:
        return None
    if len(data) < 32:
        return None
    ncmds = struct.unpack(f'{fmt}I', data[16:20])[0]
    offset = 32
    for _ in range(ncmds):
        if offset + 8 > len(data):
            break
        cmd, cmdsize = struct.unpack(f'{fmt}II', data[offset:offset + 8])
        if cmd == LC_CODE_SIGNATURE:
            if offset + 16 > len(data):
                break
            dataoff, datasize = struct.unpack(f'{fmt}II', data[offset + 8:offset + 16])
            return _cdhash_from_sig(data[dataoff:dataoff + datasize])
        offset += cmdsize
    return None


def get_cdhash(filepath: str) -> str | None:
    try:
        with open(filepath, 'rb') as f:
            data = f.read()
    except OSError:
        return None

    if len(data) < 4:
        return None

    magic = struct.unpack('>I', data[:4])[0]

    if magic in (FAT_MAGIC, FAT_CIGAM):
        nfat = struct.unpack('>I', data[4:8])[0]
        best = None
        for i in range(nfat):
            off = 8 + i * 20
            if off + 20 > len(data):
                break
            cputype, _sub, arch_off, arch_size, _align = struct.unpack('>iiIII', data[off:off + 20])
            result = _cdhash_from_macho(data[arch_off:arch_off + arch_size])
            if result:
                # prefer arm64 (0x0100000C)
                if cputype == 0x0100000C:
                    return result
                best = result
        return best

    return _cdhash_from_macho(data)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print(f'usage: {sys.argv[0]} <binary>', file=sys.stderr)
        sys.exit(1)
    h = get_cdhash(sys.argv[1])
    if h:
        print(h)
