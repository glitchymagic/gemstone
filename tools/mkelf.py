#!/usr/bin/env python3
"""Wrap a raw Dreamcast SH-4 image in a minimal ELF32 (EM_SH, little-endian) so
Ghidra's ELF loader (and REA, which only takes raw ARM/x86/m68k/6502) can open it.
Bytes are copied unchanged into one PT_LOAD at the given virtual address.
  mkelf.py rip/fs/1ST_READ.BIN 0x8C010000 work/rea/1st_read.elf
  mkelf.py dumps/ryA.bin       0x8C000000 work/rea/ram_ryA.elf   (16 MB RAM dump)
"""
import struct, sys
src, base, out = sys.argv[1], int(sys.argv[2], 0), sys.argv[3]
entry = int(sys.argv[4], 0) if len(sys.argv) > 4 else (0x8C010000 if base <= 0x8C010000 else base)
data = open(src, 'rb').read()
OFF = 0x1000
ehdr = b'\x7fELF' + bytes([1, 1, 1, 0]) + b'\0' * 8
ehdr += struct.pack('<HHIIIIIHHHHHH', 2, 42, 1, entry, 52, 0, 0x9, 52, 32, 1, 0, 0, 0)
phdr = struct.pack('<IIIIIIII', 1, OFF, base, base & 0x1FFFFFFF, len(data), len(data), 7, 0x1000)
blob = ehdr + phdr
blob += b'\0' * (OFF - len(blob)) + data
open(out, 'wb').write(blob)
print(f'{out}: {len(data)} bytes at 0x{base:08X}, entry 0x{entry:08X}')
