# Gemstone: a Power Stone remaster

Capcom's **Power Stone** (Dreamcast, 1999), rebuilt in **Godot 4** from your own copy of the game: same fighters,
same stages, same moves and rules, with a new look on top. Built with AI on a Mac.

**Work in progress.** It plays, it isn't finished, and some of it is still rough. Details below, honestly.

> Not affiliated with or endorsed by Capcom. Power Stone, its characters, art, music and program belong to Capcom.
> **None of it is in this repository.** You need your own copy of the game: buy it, dump your disc, and the importer
> builds everything from that dump on your machine.

## What it is

- **The original game, measured.** Gameplay is compared frame by frame against the real disc running in an emulator
  (same pad inputs, per-frame motion, health, gems, positions). The CPU opponents run the original's own AI program,
  read from your disc. Damage, Power Change, items, gems and the arcade ladder follow the original's code.
- **Two looks.** *Remaster*: stylized PBR (skin, cloth, metal and hair shaders, normal and roughness maps, subdivided
  meshes, 4x textures, all derived from the disc's own models and textures; no new or replacement art). *Classic*: the
  disc's models and textures, sharp at any resolution.
- **Modes:** Arcade (the original ladder, Valgas and Final Valgas included), VS, Training (hit spheres + frame data),
  plus extras that never change Arcade/VS: Battle Royale for 2-4, replays, lighting remixes.
- **All 10 fighters + Final Valgas, all 11 stages.**

## Status (honest)

What works today on the developer's machine:
- Every fighter, stage and mode above. The full test suite (165 checks, 23 runs per look) passes in both looks.
- Gameplay ledger: 96 same-input recordings against the disc; most moves, chains, hit-stop, knockdowns, throws, items
  and Power Change match frame by frame.

What's still wrong or missing:
- **Some arcade runs stall.** In 8 seeded CPU-only ladder runs, 3 reached the end; the rest got stuck in long no-damage
  stretches, mostly on Kraken's ship (its upper deck) and against Final Valgas. Many CPU-vs-CPU rounds go to TIME.
- 31 logged bugs are open (launch start points, a few hit-reaction classes, Jack's air Drives, shot colours, Final
  Valgas's own moves). They're listed in [docs/BUGS.md](docs/BUGS.md).
- **This public repo can't build a playable game yet.** The importer already makes the disc's files, music, announcer,
  sound banks, hit data, the original AI program, items and HUD portraits from your dump. Not yet: the fighters'
  skeletons and animations, stage prop layouts, and the numbers that were *measured* from the original running in an
  emulator (stage walk areas, camera presets, sound cues, Power Change timelines). Those are being rewritten to read
  straight from the disc files. `python3 importer/psimport.py --report` lists exactly what's still missing, and the
  game says so instead of ever using a stand-in.

## Dump your disc

You need a dump of **Power Stone (USA)** (the importer checks every file against the known USA release):
- **.gdi** (Redump-style, e.g. from a Dreamcast + SD card loader, or a GD-ROM drive) works best.
- **.cdi**: read by scanning for the data track.
- **.chd**: needs MAME's `chdman` on your PATH (it converts to .gdi first).

## Import and play

Needs Python 3.10-3.12, `ffmpeg` and `vgmstream-cli` on PATH, and Godot 4.7.

```sh
pip install -r importer/requirements.txt
python3 importer/psimport.py "/path/to/Power Stone (USA).gdi" --godot /path/to/godot
godot --path game            # or open game/project.godot in the Godot editor and press Play
```

First run: about a minute for the disc, music, sound and tables, plus a one-time download of the two texture upscaler
networks (Real-ESRGAN anime 6B, 4x-AnimeSharp; ~85 MB, checked by hash). The Remaster look's HD build adds a few
minutes per fighter once the fighters import.

What it writes (never committed, all in `.gitignore`): `rip/fs/` (your disc's files), `game/assets/ripped|audio|
fidelity|disc|hd/`, and `game/assets/IMPORT_REPORT.json`.

## How it's built

- `game/`: the Godot project (GDScript). `game/scripts/fighter.gd` is the fighter core, `cpu_game.gd` runs the
  original's AI program, `rules.gd` the damage rules, `hd.gd` + `game/shaders/` the Remaster look.
- `tools/`: disc format decoders (models, PowerVR textures, ADX/DTPK audio, hit data), the asset pipeline, and the
  measuring kit (an emulator driver and loggers) used to compare against the original.
- `importer/`: the first-run importer. `importer/tables.py` lists every table the code reads from the program file.
- `docs/`: format notes, memory maps and the bug ledger.
- `tools/audit_clean.py`: runs on every push (GitHub Action). It fails if anything from the disc gets into the repo:
  media files, decompiler output, long number tables, or (locally, with `--disc rip/fs`) any 64-byte run that also
  appears in a disc file.

## Contributing

Issues and pull requests are welcome: bugs you see against the original, a fighter move that feels off, or help with the
open decoding work (motions from `Pn0_MOT.MDT`, stage layouts from the program file). Two rules: nothing from the game
goes in the repo (the audit enforces it), and no look-alike or stand-in art: anything new must be derived from the
disc's own data.

## License

The code is [MIT](LICENSE). Power Stone belongs to Capcom; buy the game.
