#!/usr/bin/env python3
"""Your Power Stone disc dump -> its files (rip/fs/). Reads the ISO9660 file system of the data track.
  .gdi  the high-density data track listed in the .gdi (Redump / TOSEC style dumps)
  .cdi  DiscJuggler images: the data track is found by scanning for the ISO9660 volume descriptor
  .chd  converted to .gdi first with MAME's chdman (must be on PATH or next to the importer)
Usage: disc.py IMAGE OUT_DIR"""
import os, re, shutil, struct, subprocess, sys, tempfile

RAW_LAYOUTS = [(2352, 16), (2352, 24), (2336, 8), (2048, 0)]   # sector size, user-data offset (mode 1 / mode 2 form 1)


class Track:
    def __init__(self, path, start_lba, ssize, doff, base=0):
        self.f = open(path, 'rb')
        self.start, self.ssize, self.doff, self.base = start_lba, ssize, doff, base

    def read(self, lba, size):
        n = (size + 2047) // 2048
        self.f.seek(self.base + (lba - self.start) * self.ssize)
        raw = self.f.read(n * self.ssize)
        if self.ssize == 2048:
            return raw[:size]
        return b''.join(raw[i * self.ssize + self.doff:i * self.ssize + self.doff + 2048] for i in range(n))[:size]


def parse_gdi(path):
    lines = [l.strip() for l in open(path, encoding='utf-8', errors='replace') if l.strip()]
    tracks = []
    for l in lines[1:]:
        m = re.match(r'(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+("([^"]+)"|(\S+))\s+(-?\d+)', l)
        if m:
            tracks.append(dict(no=int(m[1]), lba=int(m[2]), type=int(m[3]), ssize=int(m[4]), file=m[6] or m[7]))
    data = [t for t in tracks if t['type'] == 4 and t['lba'] >= 45000]
    if not data:
        raise SystemExit('disc: no high-density data track in ' + path)
    t = data[0]
    doff = 16 if t['ssize'] == 2352 else 0
    return Track(os.path.join(os.path.dirname(path), t['file']), t['lba'], t['ssize'], doff)


def scan_image(path):
    """Find an ISO9660 volume descriptor anywhere in a raw image and work out where its track starts."""
    size = os.path.getsize(path)
    f = open(path, 'rb')
    CH = 64 << 20
    pos = 0
    while pos < size:
        f.seek(pos); blk = f.read(CH + 8)
        for m in re.finditer(rb'\x01CD001\x01', blk):
            p = pos + m.start()
            f.seek(p); pvd = f.read(2048)
            root = pvd[156:190]
            rlba, rsize = struct.unpack_from('<I', root, 2)[0], struct.unpack_from('<I', root, 10)[0]
            for ssize, doff in RAW_LAYOUTS:
                # PVD = LBA start+16 at byte p; LBA L sits at p - doff + (L - start - 16) * ssize: solve start from the
                # root directory's own "." entry (its extent field is the root's LBA)
                for start in range(0, max(0, rlba - 16) + 1):
                    q = p - doff + (rlba - start - 16) * ssize + doff
                    if q < 0 or q + 34 > size:
                        continue
                    f.seek(q); e = f.read(34)
                    if e[0] >= 34 and struct.unpack_from('<I', e, 2)[0] == rlba and e[32] == 1 and e[33] == 0:
                        base = p - doff - 16 * ssize
                        return Track(path, start, ssize, doff, base)
        pos += CH
    raise SystemExit('disc: no ISO9660 file system found in ' + path)


def from_chd(path, tmp):
    exe = shutil.which('chdman') or shutil.which('chdman.exe')
    here = os.path.join(os.path.dirname(os.path.abspath(sys.argv[0])), 'chdman' + ('.exe' if os.name == 'nt' else ''))
    if not exe and os.path.exists(here):
        exe = here
    if not exe:
        raise SystemExit('disc: .chd needs chdman (MAME tools). Install it, or convert to .gdi first: '
                         'chdman extractcd -i game.chd -o game.gdi')
    gdi = os.path.join(tmp, 'disc.gdi')
    subprocess.run([exe, 'extractcd', '-i', path, '-o', gdi], check=True)
    return parse_gdi(gdi)


def extract(image, out):
    ext = image.lower().rsplit('.', 1)[-1]
    tmp = None
    if ext == 'gdi':
        t = parse_gdi(image)
    elif ext == 'chd':
        tmp = tempfile.mkdtemp(prefix='ps_chd_')
        t = from_chd(image, tmp)
    else:
        t = scan_image(image)
    pvd = t.read(t.start + 16, 2048)
    if pvd[1:6] != b'CD001':
        raise SystemExit('disc: the data track has no ISO9660 volume descriptor')
    os.makedirs(out, exist_ok=True)
    files = []

    def walk(lba, size, rel):
        data = t.read(lba, size)
        i = 0
        while i < len(data):
            n = data[i]
            if n == 0:
                i = (i // 2048 + 1) * 2048
                continue
            rec = data[i:i + n]
            i += n
            elba, esz, flags = struct.unpack_from('<I', rec, 2)[0], struct.unpack_from('<I', rec, 10)[0], rec[25]
            name = rec[33:33 + rec[32]]
            if name in (b'\x00', b'\x01'):
                continue
            name = name.decode('ascii', 'replace').split(';')[0]
            p = os.path.join(rel, name)
            if flags & 2:
                os.makedirs(os.path.join(out, p), exist_ok=True)
                walk(elba, esz, p)
            else:
                with open(os.path.join(out, p), 'wb') as o:
                    o.write(t.read(elba, esz))
                files.append(p)

    root = pvd[156:190]
    walk(struct.unpack_from('<I', root, 2)[0], struct.unpack_from('<I', root, 10)[0], '')
    if tmp:
        shutil.rmtree(tmp, ignore_errors=True)
    return sorted(files)


if __name__ == '__main__':
    fs = extract(sys.argv[1], sys.argv[2])
    print(len(fs), 'files ->', sys.argv[2])
