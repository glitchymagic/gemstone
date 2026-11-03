#!/usr/bin/env python3
"""Send command lines to tools/flycast_drive.lua (v2 queue protocol) and optionally wait until the queue
and all captures drain. Usage: fc.py [-w SECONDS] "line" ["line" ...]   |   fc.py -s (print status)"""
import os, re, sys, time
ROOT = os.environ.get('PS_FC_ROOT', './dumps/')   # tools/fcinst.py: other instances
CMD = ROOT + 'cmd/'
SEQ = CMD + '.seq'


def status():
    try:
        s = open(ROOT + 'status.txt').read().strip()
    except OSError:
        return {}
    return dict(re.findall(r'(\w+)=(\S*)', s))


def send(lines):
    os.makedirs(CMD, exist_ok=True)
    n = int(open(SEQ).read()) if os.path.exists(SEQ) else 1
    tmp = CMD + f'.tmp{n}'
    open(tmp, 'w').write('\n'.join(lines) + '\n')
    os.rename(tmp, CMD + f'{n:04d}.txt')
    open(SEQ, 'w').write(str(n + 1))
    return n


def wait(n, timeout):
    t0 = time.time()
    while time.time() - t0 < timeout:
        time.sleep(0.5)
        s = status()
        if int(s.get('seq', 0)) > n and s.get('queue') == '0' and s.get('wait') == '0' and s.get('caps') == '0':
            return s
    return status()


if __name__ == '__main__':
    a = sys.argv[1:]
    if a and a[0] == '-s':
        print(status()); sys.exit()
    to = 0
    if a and a[0] == '-w':
        to = float(a[1]); a = a[2:]
    n = send(a)
    if to:
        print(wait(n, to))
