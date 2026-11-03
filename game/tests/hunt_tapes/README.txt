Raw input tapes (one line per frame: P1 and P2 Dreamcast pad bits in hex, tests/tape_run.gd format) that reproduce
docs/HUNT.md findings without the fuzz:
  h1_air_punch.txt / h1_air_kick.txt  H-1: standing jump, then punch / kick on the 9th frame after the press.
  Godot --headless --path game --fixed-fps 60 -s res://tests/tape_run.gd -- tests/hunt_tapes/h1_air_punch.txt /tmp/p.jsonl stg00 falcon,ryoma
  2026-10-27: kick (core, k1/12) apex 330 cm, 36 frames airborne = the original; punch (k1/10 has no clip for Falcon,
  falls back to the old air attack) apex 618 cm, 82 frames airborne, plays k1/12, lands still in ATTACK.
