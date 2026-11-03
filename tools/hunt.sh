#!/bin/bash
# BUG-28 breakage hunt matrix (docs/HUNT.md): every fighter (10 + Final Valgas) on every stage (11), both looks, N seeds,
# both fighters human-driven by seeded fuzz (game/tests/hunt.gd fight), plus the menu flow (hunt.gd menus) per look and
# seed, plus the static sound check. Runs JOBS Godot processes at once, then prints tools/hunt_report.py's summary.
#   tools/hunt.sh                          # seeds "1", looks "remaster classic", 3600 frames per run, 4 jobs
#   SEEDS="1 2 3" FRAMES=5400 JOBS=4 HUNT_OUT=/private/tmp/x tools/hunt.sh
#   STAGES="stg00 stg80" FIGHTERS="falcon kraken" tools/hunt.sh   # a slice
# Output dir (default /tmp/ps-fx-hunt/run_MMDD_HHMM): per run NAME.jsonl / NAME.log / NAME.rc,
# summary.txt (counts per finding class: diff two runs' summary.txt), findings.json (every distinct finding + repro).
cd "$(dirname "$0")/.."
G=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
GAME=${GAME:-game}   # the Godot project to hunt in (an APFS clone with other code: before/after runs)
SEEDS=${SEEDS:-1}
LOOKS=${LOOKS:-"remaster classic"}
FRAMES=${FRAMES:-3600}
JOBS=${JOBS:-4}
STAGES=${STAGES:-"stg00 stg10 stg20 stg30 stg40 stg50 stg60 stg70 stg80 stg90 stga0"}
FIGHTERS=${FIGHTERS:-"falcon ryoma wangtang jack gunrock galuda ayame rouge kraken valgas finalvalgas"}
MENUS=${MENUS:-1}
OUT=${HUNT_OUT:-/tmp/ps-fx-hunt/run_$(date +%m%d_%H%M)}
mkdir -p "$OUT"
# the run hunts a snapshot (APFS clone) of the game taken now: edits made while it runs don't mix into later runs
git rev-parse --short HEAD > "$OUT/commit.txt" 2>/dev/null; git status --short -- game | head -20 >> "$OUT/commit.txt"
if [ "${SNAPSHOT:-1}" = 1 ]; then
  [ -d "$OUT/game_snapshot" ] || cp -cR "$GAME" "$OUT/game_snapshot"   # same OUT again: the first snapshot is reused
  GAME="$OUT/game_snapshot"
fi
read -r -a F <<< "$FIGHTERS"
nf=${#F[@]}
list="$OUT/jobs.txt"; : > "$list"
for look in $LOOKS; do
  for seed in $SEEDS; do
    si=0
    for st in $STAGES; do
      # every fighter once on every stage: pairs (2k, 2k+1) of the roster rotated by the stage index
      for ((k=0; k*2<nf; k++)); do
        a=${F[$(( (2*k + si) % nf ))]}; b=${F[$(( (2*k + 1 + si) % nf ))]}
        echo "$look fight $st $a,$b $seed $FRAMES" >> "$list"
      done
      si=$((si + 1))
    done
    [ "$MENUS" = 1 ] && echo "$look menus - - $seed $((FRAMES * 3))" >> "$list"
  done
done
echo "remaster static - - 1 2" >> "$list"
run_one() {
  look=$1; mode=$2; st=$3; ch=$4; seed=$5; fr=$6
  name="${look}_${mode}_${st}_${ch/,/-}_s${seed}"
  PS_LOOK=$look timeout $(( fr / 30 + 240 )) "$G" --headless --path "$GAME" --fixed-fps 60 -s res://tests/hunt.gd -- \
    "$mode" "$st" "$ch" "$seed" "$fr" "$OUT/$name.jsonl" > "$OUT/$name.log" 2>&1
  echo $? > "$OUT/$name.rc"
}
export -f run_one; export G OUT GAME
echo "hunt: $(wc -l < "$list") runs, $JOBS at once -> $OUT"
t0=$(date +%s)
xargs -P "$JOBS" -L 1 bash -c 'run_one "$@"' _ < "$list"
echo "hunt: done in $(( $(date +%s) - t0 )) s"
python3 tools/hunt_report.py "$OUT" | tee "$OUT/summary.txt"
