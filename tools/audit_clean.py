#!/usr/bin/env python3
"""Clean-room audit: fails if the repository holds anything from the game disc.

Checks every tracked file (git ls-files; --all = every file under the tree, for a folder that isn't a repo yet):
  1. paths that only ever hold disc data or decompiler output (ripped assets, dumps, Ghidra exports, disc images)
  2. media / binary files of any kind (images, audio, models, archives, executables)
  3. decompiler-shaped text (FUN_/DAT_/LAB_ symbols, Ghidra 'undefined4' types, raw SH-4 listings)
  4. long literal number tables (>= 64 numbers in one list) and long hex blobs (>= 64 bytes)
  5. personal data (home paths, private host names, private IPs, e-mail addresses, tokens)
  6. --disc DIR: any run of >= 64 bytes that also appears in a file of DIR (the player's extracted disc).
     Not run in CI (CI has no disc); run it locally before every push.
Exit 0 = clean, 1 = findings (one line each). Usage: tools/audit_clean.py [--disc DIR] [--all] [ROOT]
"""
import argparse, os, re, subprocess, sys

WIN = 64
BANNED_PATH = re.compile(r"""(^|/)(
      game/assets/(ripped|hd|audio|fidelity|disc|upscaled)/
    | dumps/ | rip/ | _disc/ | work/ | build/ | _archive/
    | docs/(rip-proof|shots)/
    | tools/ghidra/.*\.(c|tsv|gzf|rep)$
    )""", re.X)
MEDIA_EXT = {
    'png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp', 'tga', 'dds', 'ktx', 'ktx2', 'exr', 'hdr', 'pvr', 'tiff',
    'wav', 'mp3', 'ogg', 'adx', 'flac', 'aac', 'm4a', 'opus', 'dsp',
    'glb', 'gltf', 'fbx', 'obj', 'dae', 'blend', 'mdl', 'mdt',
    'npz', 'npy', 'pck', 'res', 'scn', 'exe', 'dll', 'so', 'dylib', 'elf', 'bin', 'iso', 'gdi', 'chd', 'cdi',
    'raw', 'img', 'zip', '7z', 'rar', 'tgz', 'gz', 'xz', 'tar', 'mp4', 'avi', 'mov', 'mkv', 'pth', 'onnx',
}
BINARY_OK = set()     # paths allowed to be binary (none today)
DECOMP = re.compile(r"\b(FUN|DAT|LAB|PTR|SUB|UNK)_[0-9a-fA-F]{6,8}\b|\bundefined[1248]?\s*\*|\b(in_r\d+|unaff_r\d+|extraout_r\d+)\b"
                    r"|^\s*[0-9a-f]{8}\s+[0-9a-f]{4}\s+(mov|mov\.l|mov\.w|jsr|bsr|bra|rts)\b", re.M)
NUM = r"-?(?:0x[0-9A-Fa-f]+|\d+(?:\.\d+)?(?:e-?\d+)?)"
NUM_LIST = re.compile(r"(?:" + NUM + r"\s*,\s*){63,}" + NUM)
HEX_BLOB = re.compile(r"(?<![0-9A-Fa-f])(?:[0-9A-Fa-f]{2}[ :]?){64,}(?![0-9A-Fa-f])")
PERSONAL = [
    (re.compile(r"/Users/[A-Za-z]|/home/[a-z]+/|C:\\\\Users\\\\|C:\\Users\\", re.I), 'home path'),
    (re.compile(r"\b(jj-pc|glitchy-worker|worker-ts|macbook-pro-1|ash-games|ash-tv)\b", re.I), 'private host / folder'),
    (re.compile(r"\bssh (tower|worker|jj-pc)\b"), 'private host'),
    (re.compile(r"/private/tmp/lane-|\blane-[a-z0-9]+/"), 'lane scratch path'),
    (re.compile(r"\b100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b"), 'Tailscale IP'),
    (re.compile(r"\b192\.168\.\d{1,3}\.\d{1,3}\b|\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"), 'LAN IP'),
    (re.compile(r"[A-Za-z0-9._%+-]+@(?!example\.)[A-Za-z0-9.-]+\.[a-z]{2,}"), 'e-mail address'),
    (re.compile(r"\b(hermes|engram|telegram|photon|imessage|tv-launcher|allout/)\b", re.I), 'private tooling'),
    (re.compile(r"\bJJ\b|\bAsh\b(?! [Kk]etchum)"), 'personal name'),
    (re.compile(r"(gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9_-]{20,}|xox[abp]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16})"), 'token'),
    (re.compile(r"(?<![\d.])(\(\d{3}\) ?|\d{3}[.-])\d{3}[.-]\d{4}(?![\d.])"), 'phone number'),
]
SELF = 'tools/audit_clean.py'


def tracked(root, every):
    if every:
        out = []
        for d, ds, fs in os.walk(root):
            ds[:] = [x for x in ds if x not in ('.git', '.godot', '__pycache__')]
            out += [os.path.relpath(os.path.join(d, f), root) for f in fs]
        return sorted(out)
    r = subprocess.run(['git', '-C', root, 'ls-files', '-z'], capture_output=True, check=True)
    return sorted(x for x in r.stdout.decode().split('\0') if x)


def is_binary(b):
    return b'\0' in b[:8192]


# ---- 64-byte runs shared with the disc: polynomial rolling hash over every window, numpy-vectorised ----
P = 0x100000001B3          # odd, so it has an inverse mod 2^64


def _inv64(a):
    x = a                  # Newton iteration for the inverse of an odd number mod 2^64
    for _ in range(6):
        x = (x * (2 - a * x)) & 0xFFFFFFFFFFFFFFFF
    return x


def window_hashes(np, data):
    """uint64 hash of every WIN-byte window of data (len(data) - WIN + 1 values)."""
    n = len(data)
    if n < WIN:
        return np.zeros(0, np.uint64)
    with np.errstate(over='ignore'):
        b = np.frombuffer(data, np.uint8).astype(np.uint64) + np.uint64(1)
        pw = np.full(n, P, np.uint64); pw[0] = 1; pw = np.cumprod(pw, dtype=np.uint64)          # P^t
        iv = np.full(n, _inv64(P), np.uint64); iv[0] = 1; iv = np.cumprod(iv, dtype=np.uint64)   # P^-t
        s = np.zeros(n + 1, np.uint64); s[1:] = np.cumsum(b * pw, dtype=np.uint64)
        return (s[WIN:] - s[:-WIN]) * iv[:n - WIN + 1]


def disc_check(np, root, files, disc):
    want = {}
    for f in files:
        data = open(os.path.join(root, f), 'rb').read()
        if len(data) >= WIN:
            want[f] = window_hashes(np, data)
    if not want:
        return []
    allh = np.unique(np.concatenate(list(want.values())))
    found = set()
    CH = 8 << 20
    for d, _, fs in os.walk(disc):
        for fn in fs:
            p = os.path.join(d, fn)
            with open(p, 'rb') as fh:
                off, prev = 0, b''
                while True:
                    blk = fh.read(CH)
                    if not blk:
                        break
                    buf = prev + blk
                    h = window_hashes(np, buf)
                    hit = np.isin(h, allh, assume_unique=False)
                    if hit.any():
                        found.update(h[hit].tolist())
                    prev = buf[-(WIN - 1):]
                    off += len(blk)
    out = []
    if found:
        fset = np.array(sorted(found), np.uint64)
        for f, h in want.items():
            idx = np.nonzero(np.isin(h, fset))[0]
            if not len(idx):
                continue
            data = open(os.path.join(root, f), 'rb').read()
            # padding (64 spaces, a row of '=') is in any file; a real copy has some variety in it
            real = [int(i) for i in idx if len(set(data[i:i + WIN])) >= 8]
            if real:
                out.append(f"{f}: {len(real)} 64-byte windows also in the disc (first at byte {real[0]}: "
                           f"{data[real[0]:real[0] + 24]!r}...)")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('root', nargs='?', default=os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
    ap.add_argument('--disc', help='folder of extracted disc files (rip/fs) for the 64-byte run check')
    ap.add_argument('--all', action='store_true', help='scan every file under ROOT, not just git-tracked ones')
    a = ap.parse_args()
    root = os.path.abspath(a.root)
    files = tracked(root, a.all)
    bad = []
    text_files = []
    for f in files:
        p = os.path.join(root, f)
        if not os.path.isfile(p):
            continue
        if BANNED_PATH.search(f):
            bad.append(f"{f}: path is reserved for disc data / decompiler output")
            continue
        ext = f.rsplit('.', 1)[-1].lower() if '.' in os.path.basename(f) else ''
        data = open(p, 'rb').read()
        if f not in BINARY_OK and (ext in MEDIA_EXT or is_binary(data)):
            bad.append(f"{f}: media / binary file ({ext or 'no extension'}, {len(data)} bytes)")
            continue
        text_files.append(f)
        if f == SELF:
            continue
        t = data.decode('utf-8', 'replace')
        for rx, what in [(DECOMP, 'decompiler-shaped text'), (NUM_LIST, '>= 64-number literal table'),
                         (HEX_BLOB, '>= 64-byte hex blob')]:
            m = rx.search(t)
            if m:
                ln = t.count('\n', 0, m.start()) + 1
                bad.append(f"{f}:{ln}: {what}: {m.group(0)[:60]!r}")
        for rx, what in PERSONAL:
            m = rx.search(t)
            if m:
                ln = t.count('\n', 0, m.start()) + 1
                bad.append(f"{f}:{ln}: {what}: {m.group(0)[:40]!r}")
    if a.disc:
        try:
            import numpy as np
        except ImportError:
            print('audit_clean: --disc needs numpy', file=sys.stderr); return 2
        bad += disc_check(np, root, text_files, a.disc)
    for b in bad:
        print(b)
    print(f"audit_clean: {len(files)} files, {len(bad)} findings" + ('' if a.disc else ' (disc byte check skipped: no --disc)'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
