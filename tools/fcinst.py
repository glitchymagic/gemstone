#!/usr/bin/env python3
"""Extra Flycast instances for the fidelity pass, each with its own HOME (osx-main.mm only splits ~/.flycast per instance
when launched by launchd) and its own command / dump folder (flycast_drive.lua reads PS_FC_ROOT). Port B gets a
controller (device2 = 0), so both fighters can be human-driven by a `tape`.
  from fcinst import Inst; fi = Inst('a'); fi.start(); fi.fc([...], wait); fi.stop()
  fcinst.py start NAME | stop NAME | status NAME"""
import os, shutil, signal, subprocess, sys, time
R = './'
FLY = R + 'tools/flycast/build/Flycast.app/Contents/MacOS/Flycast'
GDI = R + '_disc/Power Stone (USA).gdi'
BASE = os.environ.get('LANE_TMP', '/tmp/ps-') + '/fc'
CFG = """[Dreamcast]
ContentPath = ./_disc

[config]
LuaFileName = flycast_drive.lua
UseReios = 1
rend.FloatVMUs = no

[input]
device1 = 0
device2 = 0
device2.1 = 10
device2.2 = 10

[window]
fullscreen = no
height = 480
left = {left}
maximized = no
top = 40
width = 640
"""


class Inst:
    def __init__(self, name):
        self.name = name
        self.dir = f'{BASE}_{name}/'
        self.root = self.dir + 'dumps/'
        self.home = self.dir + 'home/'

    def setup(self):
        fl = self.home + '.flycast/'
        os.makedirs(fl + 'data', exist_ok=True)
        for d in ('cmd', 'cap', 'shots'): os.makedirs(self.root + d, exist_ok=True)
        open(fl + 'emu.cfg', 'w').write(CFG.replace('{left}', str(40 + 60 * (hash(self.name) % 8))))
        shutil.copy(R + 'tools/flycast_drive.lua', fl + 'flycast_drive.lua')
        src = os.path.expanduser('~/.flycast/data/')
        for f in ([] if os.environ.get('FC_FRESH_VMU') else os.listdir(src)):   # FC_FRESH_VMU=1: blank VMUs (factory options)   # VMU saves (the game's options / unlocks as on the main instance)
            if f.endswith('.bin') and not os.path.exists(fl + 'data/' + f): shutil.copy(src + f, fl + 'data/' + f)

    def env(self):
        e = dict(os.environ); e['HOME'] = self.home.rstrip('/'); e['PS_FC_ROOT'] = self.root
        return e

    def start(self):
        self.stop()
        self.setup()
        for f in os.listdir(self.root + 'cmd'): os.remove(self.root + 'cmd/' + f)
        open(self.root + 'cmd/.seq', 'w').write('1')
        if os.path.exists(self.root + 'status.txt'): os.remove(self.root + 'status.txt')
        p = subprocess.Popen([FLY, GDI], stdout=open(self.dir + 'flycast.log', 'w'), stderr=subprocess.STDOUT,
                             start_new_session=True, env=self.env())
        open(self.dir + 'pid', 'w').write(str(p.pid))
        time.sleep(4)
        return p

    def stop(self):
        try:
            pid = int(open(self.dir + 'pid').read())
            os.kill(pid, signal.SIGKILL); time.sleep(1)
        except (OSError, ValueError):
            pass

    def fc(self, lines, wait=600):
        r = subprocess.run([sys.executable, R + 'tools/fc.py', '-w', str(wait), *lines], check=True, text=True,
                           capture_output=True, env=self.env())
        return r.stdout

    def status(self):
        try:
            import re
            return dict(re.findall(r'(\w+)=(\S*)', open(self.root + 'status.txt').read()))
        except OSError:
            return {}

    def idle(self):
        s = self.status()
        return s.get('queue') == '0' and s.get('wait') == '0' and s.get('caps') == '0'

    def wait_idle(self, timeout=3600, poll=2.0):
        t0 = time.time()
        while time.time() - t0 < timeout:
            time.sleep(poll)
            if self.idle(): return True
        return False

    def log(self):
        return open(self.dir + 'flycast.log', errors='replace').read()


if __name__ == '__main__':
    i = Inst(sys.argv[2])
    if sys.argv[1] == 'start': print(i.start().pid)
    elif sys.argv[1] == 'stop': i.stop()
    else: print(i.status())
