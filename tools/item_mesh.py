#!/usr/bin/env python3
"""Item chest + item meshes off the disc (fx-item2, docs/ITEMS.md 5-6) -> game/assets/ripped/items/*.glb (untracked)
and the tracked game/assets/fidelity/items.json (which parts make which item, from the game's own tables).
Source: the common model bank inside 1ST_READ.BIN at file offset 0x171088 (324 parts, tools/psmdl.py layout; the bank
has no texture table of its own). Texture sets: EFKY_MODEL.BIN with the 41-entry table at 1ST_READ 0x1C7414 (gems,
chest: parts use material texture 0..40), ITEM_MODEL.BIN with the 2-entry table at 0x1C76B4 (the items, two 256x256
VQ 565 textures; the blob sizes match both tables exactly: 143872 / 36864 bytes).
Which part is which item: the item object's init (0x0C05A990..) sets node +0x2E0 to bank entry byte 0 of the 4-byte
record 0x0C335F28 + id * 4 (bank 0x0C664988 = the 35 part pointers at 0x0C1D6D70: entries 0-15 -> parts 142-157, then
161, 162, 158, 159, 160, 176, 174, 175, 163-173); the thrown items 7 / 8 / 9 add two nodes from 0x0C33C7A8
[12, 11, 14, 13, 12, 11] (0x0C0C63C4(obj, 2 / 1 / 0)), both at the object's origin. Logged in RAM (fx-item, Flycast
i1): item 2 = part 144, item 8 = part 149 + its extra nodes. Effect nodes (item 1 / 10: common-bank effects 121 / 132)
are not part of the mesh. Chest = parts 56, 126, 57, 58, 59 (+ 127, the light shaft of the opening, own file).
  item_mesh.py [out_dir]"""
import json, os, struct, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import psmdl, export_glb

R = './'
FS = R + 'rip/fs/'
BASE = 0x0C010000
BANK = 0x171088
EFKY_TAB, EFKY_N = 0x1C7414, 41
ITEM_TAB, ITEM_N = 0x1C76B4, 2
PTRS = 0x0C1D6D70
REC = 0x0C335F28
EXTRA = 0x0C33C7A8
REC_TAB = 0x0C33AB08
CHEST = [56, 126, 57, 58, 59]
CHEST_LIGHT = [127]


def main(out):
    exe = open(FS + '1ST_READ.BIN', 'rb').read()
    bank = exe[BANK:]
    parts, _, _ = psmdl.parse(bank)
    end = parts[-1]['end']
    off2i = {p['ofs']: i for i, p in enumerate(parts)}
    ptr = struct.unpack_from('<35I', exe, PTRS - BASE)
    entry = [off2i[x - (BASE + BANK)] for x in ptr]
    extra = list(exe[EXTRA - BASE:EXTRA - BASE + 6])
    items = {}
    for i in range(18):
        b0 = exe[REC - BASE + 4 * i]
        ps = [entry[b0]]
        if i in (7, 8, 9):
            k = {7: 2, 8: 1, 9: 0}[i]
            ps += [entry[extra[k * 2]], entry[extra[k * 2 + 1]]]
        items[i] = ps
    os.makedirs(out, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='itemmesh_')

    def mdl_with(tab, n):   # the bank's parts + a texture table so export_glb can decode the set
        p = tmp + f'/bank_{tab:x}.mdl'
        open(p, 'wb').write(bank[:end] + exe[tab:tab + 16 * n] + b'\0' * 16)
        return p
    efky = mdl_with(EFKY_TAB, EFKY_N)
    itm = mdl_with(ITEM_TAB, ITEM_N)
    export_glb.build(efky, FS + 'EFKY_MODEL.BIN', out + '/chest.glb', None, set(CHEST), None, 'chest')
    export_glb.build(efky, FS + 'EFKY_MODEL.BIN', out + '/chest_light.glb', None, set(CHEST_LIGHT), None, 'chest_light')
    for i in range(18):
        export_glb.build(itm, FS + 'ITEM_MODEL.BIN', out + f'/item{i:02d}.glb', None, set(items[i]), None, f'item{i:02d}')
    sph = {i: [round(v, 2) for v in parts[p]['sphere']] for i in range(18) for p in items[i][:1]}
    meta = {
        '_doc': 'fx-item2: chest + item meshes (tools/item_mesh.py -> game/assets/ripped/items/, untracked). Parts of the '
                '1ST_READ common bank (file offset 0x171088); per-id node 0 = bank entry byte 0 of 0x0C335F28 + id*4, '
                'items 7 / 8 / 9 + two nodes from 0x0C33C7A8. Textures: chest EFKY_MODEL.BIN (table 0x1C7414), items '
                'ITEM_MODEL.BIN (table 0x1C76B4).',
        'chest_parts': CHEST, 'chest_light_parts': CHEST_LIGHT,
        'item_parts': {str(i): items[i] for i in range(18)},
        'item_sphere_cm': {str(i): sph[i] for i in range(18)},
        'item_records': [exe[REC_TAB - BASE + 20 * k:REC_TAB - BASE + 20 * k + 20].hex() for k in range(70)],
        'item_records_src': '1ST_READ 0x0C33AB08 + 20 * index (the object / item attack records, OBJ.md 6b): b0 reaction '
                            'class, b1 base damage (of 240), b2 hit-stop, b4 record type (7 = no gem / PC bonus)',
        'glb': {'chest': 'res://assets/ripped/items/chest.glb', 'chest_light': 'res://assets/ripped/items/chest_light.glb',
                'item': 'res://assets/ripped/items/item%02d.glb'},
    }
    return meta


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else R + 'game/assets/ripped/items'
    meta = main(out)
    print(json.dumps(meta['item_parts']))
    fid = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(out))), 'fidelity', 'items.json')
    if len(sys.argv) > 2: fid = sys.argv[2]
    json.dump(meta, open(fid, 'w'), indent=1)
    print('wrote', out, fid)
