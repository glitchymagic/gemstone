#!/bin/bash
# Out-of-map proof (fx-oom, docs/fx-oom.md): seeded CPU-vs-CPU matches as a player sees them (tests/match_movie.gd,
# headless, no render) with PS_AUDIT on every stage in both looks, plus 4-fighter Battle Royale on a few stages;
# tools/cam_audit.py counts the frames a fighter's feet are not over the stage's own floor inside the original's
# playable area (out_of_map) and gems / throwables (obj_out).
# Usage: tools/oom_proof.sh [OUTDIR] [JOBS]    -> OUTDIR/summary.txt (one line per run), exit 1 if any frame is out
cd "$(dirname "$0")/.."
G=/Applications/Godot.app/Contents/MacOS/Godot; PY=${PY:-$HOME/.pyenv/versions/3.11.11/bin/python3}
OUT=${1:-/tmp/ps_oom_$(basename "$PWD")}; J=${2:-4}; mkdir -p "$OUT"
SEED=${PS_SEED:-7}
runs=()
for look in remaster classic; do
  for st in ${PS_STAGES:-stg00 stg10 stg20 stg30 stg40 stg50 stg60 stg70 stg80 stg90 stga0}; do
    ch=falcon,ryoma; [ $st = stga0 ] && ch=falcon,finalvalgas
    runs+=("$look $st $ch")
  done
done
for st in ${PS_BR_STAGES:-stg00 stg40 stg80}; do runs+=("remaster $st falcon,ryoma,wangtang,gunrock"); done
one() {
  local look=$1 st=$2 ch=$3; local tag=${look}_${st}_$(echo $ch | tr ',' '-')
  PS_SEED=$SEED PS_LOOK=$look PS_AUDIT=$OUT/$tag.jsonl timeout 1500 $G --headless --path game --fixed-fps 60 \
    -s res://tests/match_movie.gd -- $st $ch 21600 > $OUT/$tag.log 2>&1
  local au a c; au=$($PY tools/cam_audit.py $OUT/$tag.jsonl 2>/dev/null)
  a=$(echo "$au" | grep -E "^(out_of_map|obj_out)" | awk '{printf "%s=%s ", $1, $2}')
  # the fight camera (BUG-3): % of fight-camera frames with a fighter hidden / head / feet cut (cam_audit.py)
  c=$(echo "$au" | grep -E "^(occluded|head_cut|feet_cut)" | awk '{printf "%s=%s ", $1, $6}')
  echo "$tag frames=$(wc -l < $OUT/$tag.jsonl | tr -d ' ') $(grep -o 'MATCH_OVER.*' $OUT/$tag.log | head -1) $a $c"
}
export -f one; export G OUT SEED PY
printf '%s\n' "${runs[@]}" | xargs -P "$J" -I{} bash -c 'one {}' | sort > "$OUT/summary.txt"
cat "$OUT/summary.txt"
! grep -vqE "out_of_map=0 obj_out=0 " "$OUT/summary.txt"
