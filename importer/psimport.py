#!/usr/bin/env python3
"""Gemstone importer: builds everything the remaster needs from YOUR Power Stone (USA) disc dump.

  python3 importer/psimport.py "Power Stone (USA).gdi"          # .gdi / .cdi / .chd
  python3 importer/psimport.py DISC --steps tables,audio         # only some steps (see STEPS)
  python3 importer/psimport.py --report                          # what is imported and what is missing

Everything goes under the checkout: rip/fs (the disc's files), game/assets/{ripped,audio,fidelity,disc,hd}. None of it
is ever committed (.gitignore). game/assets/IMPORT_REPORT.json says what was made and what could not be: the game reads
it and tells you, it never fills a gap with a substitute.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
FS = os.path.join(ROOT, 'rip', 'fs')
ASSETS = os.path.join(ROOT, 'game', 'assets')
REPORT = os.path.join(ASSETS, 'IMPORT_REPORT.json')
PY = sys.executable


def log(*a):
    print('[import]', *a, flush=True)


def run(args, **kw):
    log('$', ' '.join(os.path.relpath(a, ROOT) if isinstance(a, str) and a.startswith(ROOT) else str(a) for a in args))
    r = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        raise RuntimeError((r.stdout[-1500:] + '\n' + r.stderr[-1500:]).strip())
    return r.stdout


def tool(name, *args):
    return run([PY, os.path.join(ROOT, 'tools', name)] + list(args))


def sha256(p):
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for blk in iter(lambda: f.read(1 << 20), b''):
            h.update(blk)
    return h.hexdigest()


# ---------------------------------------------------------------- steps
def step_deps(a, rep):
    miss = []
    for mod in ('numpy', 'PIL', 'torch', 'spandrel', 'scipy'):
        # some Python builds lack _lzma; torchvision only imports it (tools/upscale.py has the same stand-in module)
        shim = ('import sys, types\ntry:\n import lzma\nexcept ImportError:\n m = types.ModuleType("lzma"); '
                'm.open = None; m.LZMAFile = None; m.LZMAError = Exception; sys.modules["lzma"] = m\n')
        if subprocess.run([PY, '-c', shim + f'import {mod}'], capture_output=True).returncode != 0:
            miss.append(mod)
    tools = [t for t in ('vgmstream-cli', 'ffmpeg') if not shutil.which(t)]
    if miss or tools:
        raise RuntimeError('missing: ' + ', '.join(miss + tools) + f' (Python {sys.executable}). Run: '
                           f'"{sys.executable}" -m pip install -r importer/requirements.txt'
                           + ('; and put ffmpeg + vgmstream-cli on PATH' if tools else ''))
    return {'python': sys.version.split()[0]}


def step_disc(a, rep):
    known = json.load(open(os.path.join(HERE, 'known_files.json')))
    have = os.path.isdir(FS) and all(os.path.exists(os.path.join(FS, n)) for n in known['files'])
    if not have:
        if not a.disc:
            raise RuntimeError('point me at your Power Stone disc: a .gdi, .cdi or .chd dump of your own copy')
        import disc
        disc.extract(a.disc, FS)
    bad = [n for n, (size, h) in known['files'].items()
           if not os.path.exists(os.path.join(FS, n)) or os.path.getsize(os.path.join(FS, n)) != size
           or (n in known['hash_check'] and sha256(os.path.join(FS, n)) != h)]
    if bad:
        raise RuntimeError(f"this isn't the Power Stone (USA) disc the importer knows ({len(bad)} files differ, e.g. "
                           f"{', '.join(bad[:4])}). Other regions are not supported yet.")
    return {'files': len(known['files'])}


# upscaler weights (not ours, not Capcom's: downloaded from their authors' releases, checked by hash)
MODELS = {
    'RealESRGAN_x4plus_anime_6B.pth': (
        'https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.2.4/RealESRGAN_x4plus_anime_6B.pth',
        'f872d837d3c90ed2e05227bed711af5671a6fd1c9f7d7e91c911a61f155e99da'),
    '4x-AnimeSharp.pth': (
        'https://huggingface.co/Kim2091/AnimeSharp/resolve/main/4x-AnimeSharp.pth',
        'e7a7de2dafd7331c1992862bbbcd9e9712a9f9f8e6303f0aaa59b4341d359bab'),
}
BIN = os.path.join(ROOT, 'tools', 'bin')


def step_models(a, rep):
    import urllib.request
    os.makedirs(BIN, exist_ok=True)
    got = []
    for name, (url, h) in MODELS.items():
        p = os.path.join(BIN, name)
        if os.path.exists(p) and sha256(p) == h:
            continue
        log('  downloading', name)
        urllib.request.urlretrieve(url, p + '.part')
        if sha256(p + '.part') != h:
            raise RuntimeError(f'{name}: download does not match its known hash ({url})')
        os.replace(p + '.part', p)
        got.append(name)
    os.environ['PS_UPSCALERS'] = BIN
    return {'downloaded': got}


def step_tables(a, rep):
    import tables
    os.makedirs(os.path.join(ASSETS, 'disc'), exist_ok=True)
    b = open(os.path.join(FS, '1ST_READ.BIN'), 'rb').read()
    out = os.path.join(ASSETS, 'disc', 'tables.json')
    json.dump(tables.build(b), open(out, 'w'), indent=1)
    return {'tables': len(tables.SPEC)}


def step_code_tables(a, rep):
    """the original's AI program, Final Valgas's AI, the movement table: read out of 1ST_READ by their tools"""
    os.makedirs(os.path.join(ASSETS, 'fidelity'), exist_ok=True)
    tool('cpu_ai.py', 'export')
    tool('fv_ai.py', 'export')
    tool('move_table.py')
    return {'made': ['fidelity/cpu_ai.json', 'fidelity/fv_ai.json', 'fidelity/move_table.json']}


def step_hits(a, rep):
    os.makedirs(os.path.join(ASSETS, 'ripped'), exist_ok=True)
    tool('hitdata.py', 'export', os.path.join(ASSETS, 'ripped') + '/')
    return {'made': sorted(f for f in os.listdir(os.path.join(ASSETS, 'ripped')) if f.endswith('_hit.json'))}


def step_ladder(a, rep):
    import ladder
    os.makedirs(os.path.join(ASSETS, 'ripped'), exist_ok=True)
    b = open(os.path.join(FS, '1ST_READ.BIN'), 'rb').read()
    json.dump(ladder.build(b), open(os.path.join(ASSETS, 'ripped', 'ladder.json'), 'w'), indent=1)
    return {}


def step_audio(a, rep):
    for exe in ('vgmstream-cli', 'ffmpeg'):
        if not shutil.which(exe):
            raise RuntimeError(f'audio needs {exe} on PATH')
    out = os.path.join(ASSETS, 'audio')
    run(['bash', os.path.join(ROOT, 'tools', 'adx_to_mp3.sh'), FS, out])
    tool('sfx_extract.py')
    n = len([f for f in os.listdir(out) if f.endswith('.mp3')])
    return {'music': n, 'se': len(os.listdir(os.path.join(out, 'se'))) if os.path.isdir(os.path.join(out, 'se')) else 0}


def step_faces(a, rep):
    tool('export_faces.py')
    return {}


def step_items(a, rep):
    tool('item_mesh.py', os.path.join(ASSETS, 'ripped', 'items'))
    return {}


def step_fighters(a, rep):
    """all 21 fighter forms: rig + textures (4x upscale) + every motion, decoded from Pn0_MOT.MDT and 1ST_READ"""
    out = tool('fighters_import.py')
    forms = [json.loads(l) for l in out.splitlines() if l.startswith('{')]
    return {'forms': len(forms), 'clips': sum(f['clips'] for f in forms),
            'not_on_disc': 'braids / ribbons / charms (the game simulates them; they keep their rest pose), '
                           'parts that leave their bone mid-move (thrown props, Ryoma\'s sword in some moves)'}


STAGES = ['STG00', 'STG10', 'STG20', 'STG30', 'STG40', 'STG50', 'STG60', 'STG70', 'STG80', 'STG90', 'STGA0']


def step_stages(a, rep):
    """11 stages: world + every prop (4x textures), prop placement from 1ST_READ (tools/stage_layout_disc.py)"""
    made = {}
    for stg in STAGES:
        tex, up = os.path.join(ROOT, 'rip', 'tex', stg), os.path.join(ROOT, 'rip', 'up', stg)
        if not os.path.isdir(tex) or not os.listdir(tex):
            tool('hd_tex.py', 'decode', stg, tex)
        tool('upscale.py', tex, up)
        tool('export_stage.py', stg, 'disc')
        made[stg.lower()] = len(json.load(open(os.path.join(ASSETS, 'ripped', stg.lower() + '_layout.json'))))
    return {'placed_objects': made, 'not_on_disc_yet': 'spawn points, camera angles (see step measured)'}


def step_hd(a, rep):
    """the Remaster look's fighters: 4x textures + derived maps (tools/hd_tex.py fighter) and subdivided meshes
    (tools/hd_mesh.py), ~2 min per form"""
    hd = os.path.join(ASSETS, 'hd')
    done = []
    for f in sorted(x[:-4] for x in os.listdir(os.path.join(ASSETS, 'ripped')) if re.fullmatch(r'p[0-9a]\d\.glb', x)):
        tex = os.path.join(hd, 'tex', f)
        tool('hd_tex.py', 'fighter', f.upper(), tex)
        out = os.path.join(hd, f + '.glb')
        if not os.path.exists(out):
            tool('hd_mesh.py', os.path.join(ASSETS, 'ripped', f + '.glb'), out, '--seg', '4', '--tex', tex,
                 '--clips', os.path.join(ASSETS, 'ripped', f + '_clips.json'))
        done.append(f)
    return {'forms': len(done)}


# Numbers measured from the original running in an emulator (its RAM, sound chip and camera logged frame by frame).
# They are not files on the disc, so the importer cannot make them yet; each needs a decoder of the game code that
# produces them. Without one the game runs that part on its own simpler rules and says so (IMPORT_REPORT.json).
MEASURED = {
    'stgNN_area.json (11)': 'the exact walkable area of each stage (where the original stops you, ledges, holes)',
    'stgNN_cam.json (11)': 'camera angles per stage area',
    'spawns.json': 'round start points per stage',
    'flow.json': 'where the winner / loser stand after a round',
    'pc_moves.json, pc_code.json': 'Power Change: transform / revert timelines and the Power Drive / Fusion moves',
    'pc_shots.json, pc_shot_look.json, pc_spin.json, fv_shots.json, fv_attacks.json': 'Drive / Fusion shots and '
        'Final Valgas\'s beams',
    'chains.json, motions.json, reactions.json, react_code.json': 'which motion each press starts, per-motion travel, '
        'hit reactions (knockback, launches)',
    'throws.json, hitgrabs.json': 'grab-throws and hit-grabs',
    'obj_code.json, item_code.json, mv_stage.json, breakables.json': 'object / pole / item / breakable rules',
    'body_scale.json, hip_pin.json, bone_boxes.json, fighter_radius.json, ground_samples.json': 'body sizes, '
        'attack reach, floor heights',
    'sfx_map.json': 'which sound each motion frame and hit plays',
    'cpu_stats.json': 'the original CPU\'s measured behaviour (test reference only)',
}


def step_measured(a, rep):
    raise NotImplementedError('not on the disc as files: ' + '; '.join(f'{k}: {v}' for k, v in MEASURED.items()))


STEPS = [
    ('deps', step_deps), ('disc', step_disc), ('models', step_models), ('tables', step_tables),
    ('code_tables', step_code_tables), ('hits', step_hits), ('ladder', step_ladder), ('audio', step_audio),
    ('faces', step_faces), ('items', step_items),
    ('fighters', step_fighters), ('stages', step_stages), ('measured', step_measured),
    ('hd', step_hd),
]


def godot_import(a, rep):
    g = a.godot or shutil.which('godot') or shutil.which('Godot')
    if not g:
        log('no Godot found: run  godot --headless --path game --import  once before playing')
        return
    run([g, '--headless', '--path', os.path.join(ROOT, 'game'), '--import'], timeout=3600)


def main():
    ap = argparse.ArgumentParser(description='Build the remaster\'s assets from your own Power Stone disc.')
    ap.add_argument('disc', nargs='?', help='your disc dump: .gdi, .cdi or .chd')
    ap.add_argument('--steps', default='all', help='comma list of: ' + ','.join(n for n, _ in STEPS))
    ap.add_argument('--godot', help='Godot 4.7 binary for the final asset import (default: godot on PATH)')
    ap.add_argument('--no-godot', action='store_true')
    ap.add_argument('--report', action='store_true', help='print the last import report and exit')
    a = ap.parse_args()
    if a.report:
        print(open(REPORT).read() if os.path.exists(REPORT) else 'not imported yet'); return 0
    want = [n for n, _ in STEPS] if a.steps == 'all' else a.steps.split(',')
    rep = json.load(open(REPORT)) if os.path.exists(REPORT) else {'steps': {}}
    t0 = time.time()
    failed = False
    for name, fn in STEPS:
        if name not in want:
            continue
        s = time.time()
        log(f'step {name}')
        try:
            info = fn(a, rep)
            rep['steps'][name] = {'ok': True, 'secs': round(time.time() - s, 1), **(info or {})}
        except NotImplementedError as e:
            rep['steps'][name] = {'ok': False, 'missing': str(e)}
            log(f'  missing: {e}')
        except Exception as e:  # noqa: BLE001 - every failure goes in the report the game shows
            rep['steps'][name] = {'ok': False, 'error': str(e)[-2000:]}
            log(f'  FAILED: {e}')
            failed = True
            if name in ('deps', 'disc'):
                break
    if not a.no_godot and not failed:
        godot_import(a, rep)
    rep['when'] = time.strftime('%Y-%m-%d %H:%M:%S')
    rep['secs'] = round(time.time() - t0, 1)
    disc_steps = [n for n, _ in STEPS if n != 'measured']
    # complete = everything the disc holds is imported; 'measured' (not on the disc as files yet) is listed, not needed
    rep['complete'] = all(rep['steps'].get(n, {}).get('ok') for n in disc_steps)
    rep['not_in_this_build'] = MEASURED
    os.makedirs(ASSETS, exist_ok=True)
    json.dump(rep, open(REPORT, 'w'), indent=1)
    log('report ->', os.path.relpath(REPORT, ROOT), '| complete' if rep['complete'] else '| incomplete (see report)')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
