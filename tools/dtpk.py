#!/usr/bin/env python3
"""Extract samples from Power Stone's DTPK sound banks (FOKER.BIN, COMMON.BIN, ...) to WAV.
Header: 'DTPK' ... u32 section offsets at 0x20..0x3C; 0x3C -> sample table:
  u32 count, then count x 16 bytes: u24 offset, u8 fmt, u32 (u16 ?, u16 loop/len), u32 0, u32 size.
sample count ~2x bytes -> 4-bit AICA ADPCM (low nibble first); ~1x -> PCM8; ~0.5x -> PCM16.
(fmt bit 1 looks like a loop flag.)
Usage: dtpk.py BANK.BIN outdir [rate]"""
import os, struct, sys, wave
import numpy as np

STEP = [230, 230, 230, 230, 307, 409, 512, 614]
DIFF = [1, 3, 5, 7, 9, 11, 13, 15, -1, -3, -5, -7, -9, -11, -13, -15]

def aica(data):
    out = np.empty(len(data) * 2, np.int16); h = 0; st = 127; k = 0
    for b in data:
        for nib in (b & 15, b >> 4):
            h += (st * DIFF[nib]) // 8
            h = -32768 if h < -32768 else 32767 if h > 32767 else h
            st = (st * STEP[nib & 7]) >> 8
            st = 127 if st < 127 else 24576 if st > 24576 else st
            out[k] = h; k += 1
    return out

def extract(path, outdir, rate=22050):
    d = open(path, 'rb').read()
    assert d[:4] == b'DTPK', path
    tab = struct.unpack_from('<I', d, 0x3C)[0]
    n = struct.unpack_from('<I', d, tab)[0]
    os.makedirs(outdir, exist_ok=True)
    res = []
    for i in range(n):
        e = tab + 4 + i * 16
        ofs = struct.unpack_from('<I', d, e)[0] & 0xFFFFFF
        fmt = d[e + 3]
        a, b = struct.unpack_from('<HH', d, e + 4)
        size = struct.unpack_from('<I', d, e + 12)[0]
        raw = d[ofs:ofs + size]
        if b >= size * 1.9: pcm = aica(raw)           # 4-bit: sample count ~ 2 x bytes
        elif b >= size * 0.9: pcm = (np.frombuffer(raw, np.int8).astype(np.int16) << 8)
        else: pcm = np.frombuffer(raw[:len(raw) // 2 * 2], '<i2')
        fn = f'{outdir}/{os.path.basename(path)[:-4].lower()}_{i:03d}.wav'
        with wave.open(fn, 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate); w.writeframes(pcm.astype('<i2').tobytes())
        rms = float(np.sqrt(np.mean(pcm.astype(np.float64) ** 2))) if len(pcm) else 0
        res.append((i, hex(ofs), fmt, a, b, size, round(len(pcm) / rate, 2), int(rms)))
    return res

if __name__ == '__main__':
    r = extract(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 22050)
    for x in r[:12]: print(x)
    print(len(r), 'samples')
