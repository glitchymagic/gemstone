#!/usr/bin/env python3
"""BUG-36: which sample the ORIGINAL plays for which action. One input tape (tools/tapes.py) is played into Flycast with
both fighters human (tools/reflog.py boot/play), logged per frame in the reflog schema (state / motion kind+id / motion
frame / health ...) AND, in the same frames, the sound chip: a Lua watcher (generated here, hot-loaded with the driver's
`lua` command right before `tapelog` + `tape`, so its frame k = the tape log's row k) reads the 64 AICA channels'
+0x00 (KYONB / PCMS / SA high) and +0x04 (SA low) every vblank and writes a line whenever one changes, with the
channel's LSA +0x08, LEA +0x0C, OCT/FNS +0x18, DISDL/DIPAN +0x24 and TL +0x28. After the tape: sound RAM (2 MB at
0x00800000) once, to place the banks (tools/sndmap.py).
  sndlog.py run INST TAPE[,TAPE...]     -> $OUT/NAME.jsonl (reflog rows), NAME.keys (AICA changes), NAME_sndram.bin
  sndlog.py cpu INST P1:P2,... [FRAMES] -> cpu_P1_P2.*: CPU vs CPU on P2's home stage (every stage's own bank)
Each tape boots its own fight (its '#! p1=.. p2=..' header) so a run starts like the remaster's tape_run.gd."""
import json, os, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reflog, tapes
from fcinst import Inst

WT = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) + '/'
OUT = os.environ.get('SND_OUT', '/tmp/ps-fx-snd/disc/')
P1, P2 = reflog.P1, reflog.P2

LUA = r'''
local OUT = "%(out)s"
local N = %(n)d
local f = io.open(OUT, "w")
local p0, p4 = {}, {}
for ch = 0, 63 do p0[ch] = -1; p4[ch] = -1 end
local k = 0
local base = cbVBlank
local rd = flycast.memory.read32
flycast_callbacks.vblank = function()
  base()
  if k >= N then return end
  for ch = 0, 63 do
    local b = 0x00700000 + ch * 0x80
    local r0 = rd(b) & 0xFFFF
    local r4 = rd(b + 4) & 0xFFFF
    if r0 ~= p0[ch] or r4 ~= p4[ch] then
      f:write(string.format("%%d %%d %%04X %%04X %%04X %%04X %%04X %%04X %%04X\n", k, ch, r0, r4, rd(b + 8) & 0xFFFF,
        rd(b + 0xC) & 0xFFFF, rd(b + 0x18) & 0xFFFF, rd(b + 0x24) & 0xFFFF, rd(b + 0x28) & 0xFFFF))
      p0[ch] = r0; p4[ch] = r4
    end
  end
  k = k + 1
  if k >= N then f:close(); flycast_callbacks.vblank = base end
end
print("[snd] watcher armed " .. OUT)
'''


def play(fi, tape_txt, name):
    os.makedirs(OUT, exist_ok=True)
    n = sum(1 for l in open(tape_txt) if l.strip())
    lua = f'{OUT}{name}_watch.lua'
    open(lua, 'w').write(LUA % {'out': f'{OUT}{name}.keys', 'n': n})
    fi.fc([f'dump {name}_ram.bin 0x0C000000 0x1000000'], 60)
    fi.wait_idle(60)
    import ladder
    opp, stg = ladder.who(fi.root + f'{name}_ram.bin')
    os.remove(fi.root + f'{name}_ram.bin')
    lines = [f'freeze8 0x{P2 + 0x71ED:08X} 0', f'freeze8 0x{P1 + 0x71ED:08X} 0', 'until8 0x0C7F302C 3 6000',
             'poke32 0x0C346A50 1', f'lua {lua}', f'tapelog {name} {reflog.segs()}', f'tape {tape_txt}',
             'wait 2', f'dump {name}_sndram.bin 0x00800000 0x200000']
    fi.fc(lines, 60)
    fi.wait_idle(n / 60 * 6 + 300)
    time.sleep(1)
    rows = reflog.decode(fi.root + f'cap/{name}.bin')
    os.replace(fi.root + f'cap/{name}.bin', OUT + name + '.bin')
    os.replace(fi.root + f'{name}_sndram.bin', OUT + name + '_sndram.bin')
    reflog.write_jsonl(rows, OUT + name + '.jsonl')
    json.dump({'p2': opp, 'stage': stg.lower(), 'tape': os.path.basename(tape_txt), 'frames': len(rows)},
              open(OUT + name + '.meta.json', 'w'))
    return rows


def cpu(fi, name, frames):
    """CPU vs CPU (both CPU flags held at 1), healths held at 240 (a hit = a one-frame dip: freezes run after the
    captures), the round clock held at 99: FRAMES of the game's own play on P2's home stage, logged like play()."""
    os.makedirs(OUT, exist_ok=True)
    lua = f'{OUT}{name}_watch.lua'
    open(lua, 'w').write(LUA % {'out': f'{OUT}{name}.keys', 'n': frames})
    hp = [f'freeze16 0x{b + 0x71D4 + 2 * k:08X} 240' for b in (P1, P2) for k in range(3)]
    lines = [f'freeze8 0x{P2 + 0x71ED:08X} 1', f'freeze8 0x{P1 + 0x71ED:08X} 1', 'until8 0x0C7F302C 3 6000'] + hp + \
            ['freeze8 0x0C7F304D 99', f'lua {lua}', f'capseg {name} {frames} {reflog.segs()}', f'wait {frames + 2}',
             f'dump {name}_sndram.bin 0x00800000 0x200000']
    fi.fc(lines, 60)
    fi.wait_idle(frames / 60 * 6 + 300)
    time.sleep(1)
    rows = reflog.decode(fi.root + f'cap/{name}.bin')
    os.replace(fi.root + f'cap/{name}.bin', OUT + name + '.bin')
    os.replace(fi.root + f'{name}_sndram.bin', OUT + name + '_sndram.bin')
    reflog.write_jsonl(rows, OUT + name + '.jsonl')
    return rows


def run_cpu(inst, pairs, frames=3600):
    """pairs 'p1:p2,...' -> runs cpu_P1_P2 (P2's home stage)"""
    fi = Inst(inst)
    try:
        for pr in pairs:
            a, b = pr.split(':')
            name = f'cpu_{a}_{b}'
            t0 = time.time()
            reflog.boot(fi, a, b)
            fi.fc([f'dump {name}_ram.bin 0x0C000000 0x1000000'], 60)
            fi.wait_idle(60)
            import ladder
            opp, stg = ladder.who(fi.root + f'{name}_ram.bin')
            os.remove(fi.root + f'{name}_ram.bin')
            rows = cpu(fi, name, frames)
            json.dump({'p1': a, 'p2': opp, 'stage': stg.lower(), 'tape': None, 'frames': len(rows)},
                      open(OUT + name + '.meta.json', 'w'))
            nk = sum(1 for _ in open(OUT + name + '.keys'))
            print(f'{name}: {stg} {len(rows)} frames, {nk} AICA changes, {time.time() - t0:.0f} s', flush=True)
    finally:
        fi.stop()


def run(inst, names):
    fi = Inst(inst)
    try:
        for name in names:
            src = WT + f'game/tests/tapes/{name}.tape'
            m = tapes.meta(src)
            txt = f'{OUT}tapes/{name}.txt'
            tapes.build(src, txt)
            t0 = time.time()
            reflog.boot(fi, m['p1'], m['p2'])
            rows = play(fi, txt, name)
            nk = sum(1 for _ in open(OUT + name + '.keys'))
            print(f'{name}: {len(rows)} frames, {nk} AICA changes, {time.time() - t0:.0f} s', flush=True)
    finally:
        fi.stop()


if __name__ == '__main__':
    if sys.argv[1] == 'run':
        run(sys.argv[2], sys.argv[3].split(','))
    elif sys.argv[1] == 'cpu':   # sndlog.py cpu INST P1:P2,... [FRAMES]
        run_cpu(sys.argv[2], sys.argv[3].split(','), int(sys.argv[4]) if len(sys.argv) > 4 else 3600)
