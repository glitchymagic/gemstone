#!/bin/bash
# BUG-3 proof (docs/fx-cam.md): the original's logged fights (dumps/cap/cl<NN>.bin, cfa0.bin for the boss arena)
# replayed into this checkout's stages with the remaster's fight camera (tests/cam_replay.gd PS_MODE=remaster), then
# tools/cam_fid.py: hidden / cut % and the yaw / distance / eye-height error vs the original's camera, per stage.
# Usage: tools/cam_proof.sh OUTDIR [JOBS]   env PS_LOOK (remaster), PS_N (frames per stage, default all),
#        PS_STAGES, CAP (the logs' folder)   -> OUTDIR/summary.txt
cd "$(dirname "$0")/.."
G=/Applications/Godot.app/Contents/MacOS/Godot; PY=${PY:-$HOME/.pyenv/versions/3.11.11/bin/python3}
OUT=${1:-/tmp/ps_camproof_$(basename "$PWD")}; J=${2:-3}; mkdir -p "$OUT"
CAP=${CAP:-./dumps/cap}; LOOK=${PS_LOOK:-remaster}
one() {
  local st=$1; local tag=${st#stg}; local log=$CAP/cl$tag.bin; [ $st = stga0 ] && log=$CAP/cfa0.bin
  env PS_LOOK=$LOOK PS_STAGE=$st PS_CAMLOG=$log PS_MODE=remaster PS_AUDIT=$OUT/${LOOK}_$st.jsonl ${PS_N:+PS_N=$PS_N} \
    timeout 2400 $G --headless --path game --fixed-fps 60 -s res://tests/cam_replay.gd > $OUT/${LOOK}_$st.log 2>&1
  echo "$st $($PY tools/cam_fid.py $OUT/${LOOK}_$st.jsonl 2>&1 | tail -3 | tr '\n' ' ')"
}
export -f one; export G OUT CAP LOOK PY PS_N
printf '%s\n' ${PS_STAGES:-stg00 stg10 stg20 stg30 stg40 stg50 stg60 stg70 stg80 stg90 stga0} | xargs -P "$J" -I{} bash -c 'one {}' | sort > "$OUT/summary.txt"
cat "$OUT/summary.txt"
