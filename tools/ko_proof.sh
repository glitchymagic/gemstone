#!/bin/bash
# Round-end freeze proof (BUG-2, docs/fx-ko.md): seeded CPU-vs-CPU matches in the real flow on every stage, cinematics
# on and off, each frame from every KO to the next round checked by game/tests/ko_watch.gd (tests/ko_check.gd).
# Usage: tools/ko_proof.sh [LOGDIR] [SEEDS (default "1 2")] [GAME_DIR (default game)]  -> one KO_CHECK line per match
# env PS_JOBS = matches at once (default 4)
cd "$(dirname "$0")/.."
G=/Applications/Godot.app/Contents/MacOS/Godot
L=${1:-/tmp/ko_proof_$(basename "$PWD")}; mkdir -p "$L"
SEEDS=${2:-"1 2"}
GD=${3:-game}
ids=(falcon ryoma wangtang jack gunrock galuda ayame rouge kraken valgas)
stages=(stg00 stg10 stg20 stg30 stg40 stg50 stg60 stg70 stg80 stg90 stga0)
jobs=()
for s in $SEEDS; do
  for k in "${!stages[@]}"; do
    st=${stages[$k]}; a=${ids[$((k % 10))]}; b=${ids[$(((k + 1 + s) % 10))]}
    [ "$a" = "$b" ] && b=${ids[$(((k + 2) % 10))]}
    for c in 1 0; do jobs+=("$s $st $a,$b $c"); done
  done
done
printf '%s\n' "${jobs[@]}" | xargs -P ${PS_JOBS:-4} -L 1 bash -c '
  PS_SEED=$0 PS_CINE=$3 timeout 900 '"$G"' --headless --path '"$GD"' --fixed-fps 60 -s res://tests/ko_check.gd -- $1 $2 \
    > '"$L"'/ko_$1_$2_s$0_c$3.log 2>&1
  grep -h KO_CHECK '"$L"'/ko_$1_$2_s$0_c$3.log || echo "KO_CHECK $1 $2 cine=$3 seed=$0: NO RESULT (see log)"'
