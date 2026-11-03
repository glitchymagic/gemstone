#!/bin/bash
# One stage's probe samples -> game/assets/fidelity/STAGE_area.json, checked against the remaster's collision
# (docs/fx-oom.md): build, leave out disc surfaces / placed parts the original never stands anyone on, add floor
# patches where the original has a floor the remaster lacks, then the final tests/area_check.gd numbers.
# Usage: AREA_OUT=dir tools/area_finalize.sh STAGE [CHECKDIR]
cd "$(dirname "$0")/.."
G=/Applications/Godot.app/Contents/MacOS/Godot; PY=${PY:-$HOME/.pyenv/versions/3.11.11/bin/python3}
st=$1; C=${2:-/tmp/ps_area_$(basename "$PWD")}; mkdir -p "$C"
chk() { timeout 300 $G --headless --path game -s res://tests/area_check.gd -- $st $C/${st}_$1.json 2>&1 | grep AREA_CHECK; }
$PY tools/stage_area.py build $st --png || exit 1
chk 1; $PY tools/stage_area.py patch $st $C/${st}_1.json surf
chk 2; $PY tools/stage_area.py patch $st $C/${st}_2.json floor
chk 3; $PY tools/stage_area.py patch $st $C/${st}_3.json floor
chk 4
