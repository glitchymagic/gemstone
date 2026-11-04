#!/usr/bin/env python3
"""ADX (from the disc) -> MP3 trimmed at the loop end + loops.json (loop_offset seconds) for Godot.
Same output as tools/adx_to_mp3.sh, without bash (Windows). Needs vgmstream-cli and ffmpeg on PATH.
Usage: adx_to_mp3.py rip/fs game/assets/audio"""
import glob, os, re, subprocess, sys, tempfile


def main():
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    loops = []
    tmp = tempfile.mkdtemp(prefix='adx_')
    for f in sorted(glob.glob(os.path.join(src, '*.ADX'))):
        b = os.path.splitext(os.path.basename(f))[0]
        meta = subprocess.run(['vgmstream-cli', '-m', f], capture_output=True, text=True).stdout
        num = lambda key: (re.search(key + r'\s*(\d+)', meta) or [None, None])[1]
        rate, ls, le = num('sample rate:'), num('loop start:'), num('loop end:')
        wav = os.path.join(tmp, b + '.wav')
        subprocess.run(['vgmstream-cli', '-i', '-o', wav, f], capture_output=True, check=True)
        af = ['-af', f'atrim=end_sample={le}'] if le else []
        subprocess.run(['ffmpeg', '-loglevel', 'error', '-y', '-i', wav] + af +
                       ['-c:a', 'libmp3lame', '-q:a', '2', os.path.join(out, b + '.mp3')], check=True)
        if le:   # bc scale=6 truncates
            loops.append('"%s": %.6f' % (b, (int(ls) * 1000000 // int(rate)) / 1e6))
        os.remove(wav)
    os.rmdir(tmp)
    with open(os.path.join(out, 'loops.json'), 'w') as fh:
        fh.write('{\n' + ',\n'.join(loops) + '}\n')
    print('ADX-DONE')


if __name__ == '__main__':
    main()
