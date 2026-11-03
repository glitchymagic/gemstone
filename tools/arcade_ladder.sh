#!/bin/bash
# Seeded whole-arcade runs (game/tests/arcade_ladder.gd: both sides the game's AI, the original ladder incl. Valgas >
# Final Valgas, lost fights continued) -> OUT/<look>_<p1>_s<seed>.log + OUT/summary.txt (tools/arcade_ladder.py).
# tools/arcade_ladder.sh OUT "ryoma falcon jack" "1 2 3" [looks: "classic remaster"] [parallel: 2]
set -u
cd "$(dirname "$0")/.."
OUT=$1; P1S=$2; SEEDS=$3; LOOKS=${4:-classic}; PAR=${5:-2}
mkdir -p "$OUT"
G=/Applications/Godot.app/Contents/MacOS/Godot
for L in $LOOKS; do for P in $P1S; do for S in $SEEDS; do
  while [ "$(jobs -rp | wc -l)" -ge "$PAR" ]; do sleep 5; done
  ( PS_SEED=$S PS_LADDER_P1=$P PS_P1_FIGHT=${PS_P1_FIGHT:-7} PS_P1_LEVEL=${PS_P1_LEVEL:-31} PS_LOOK=$L timeout 7200 $G --headless --path game --fixed-fps 60 \
      -s res://tests/arcade_ladder.gd > "$OUT/${L}_${P}_s$S.log" 2>&1 ) &
done; done; done
wait
python3 tools/arcade_ladder.py "$OUT" > "$OUT/summary.txt"
cat "$OUT/summary.txt"
