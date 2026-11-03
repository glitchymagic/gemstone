#!/bin/bash
# Rebuilds game/assets/hd (untracked, like ripped/) from the disc rip + game/assets/ripped: the Remaster look's
# subdivided fighter meshes, 4x textures and derived maps. Every step skips what already exists (delete a file to
# redo it). Reads the rip from $PS_RIP (default: the master checkout's rip/, read only).
# Usage: tools/build_hd.sh [fighters|stages|all] [p00 p10 ...]      (~2 min per fighter form, then a Godot --import)
cd "$(dirname "$0")/.."
PY=${PS_PY:-$HOME/.pyenv/versions/3.11.11/bin/python3}
UP=${PS_UPPY:-python3}   # torch + spandrel (needs torch + spandrel: importer/requirements-hd.txt)
G=/Applications/Godot.app/Contents/MacOS/Godot
what=${1:-all}; shift
forms=("$@")
[ ${#forms[@]} -eq 0 ] && forms=(p00 p01 p10 p11 p20 p21 p30 p31 p40 p41 p50 p51 p60 p61 p70 p71 p80 p81 p90 p91 pa0)
mkdir -p game/assets/hd/tex
if [ "$what" = fighters ] || [ "$what" = all ]; then
  for f in "${forms[@]}"; do
    [ -f game/assets/ripped/$f.glb ] || continue
    $UP tools/hd_tex.py fighter "$(echo $f | tr a-z A-Z)" game/assets/hd/tex/$f || exit 1
    # rebuild the mesh only when it's missing, older than hd_mesh.py, or an albedo (the only map it embeds) changed;
    # not on the folder's date (Godot's .import files touch it)
    if [ ! -f game/assets/hd/$f.glb ] || [ tools/hd_mesh.py -nt game/assets/hd/$f.glb ] || \
       [ -n "$(find game/assets/hd/tex/$f -name 't[0-9][0-9].png' -newer game/assets/hd/$f.glb | head -1)" ]; then
      $PY tools/hd_mesh.py game/assets/ripped/$f.glb game/assets/hd/$f.glb --seg 4 --tex game/assets/hd/tex/$f \
        --clips game/assets/ripped/${f}_clips.json || exit 1
    fi
  done
fi
if [ "$what" = stages ] || [ "$what" = all ]; then
  [ -x tools/build_hd_stages.sh ] && { tools/build_hd_stages.sh || exit 1; }
fi
$G --headless --path game --import > /tmp/build_hd_import.log 2>&1
echo "build_hd: done ($(du -sh game/assets/hd | cut -f1))"
