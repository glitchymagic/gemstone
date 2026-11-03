#!/bin/bash
# Before/after proof stills of the Remaster look (Mac, windowed Godot): every stage (the game's own fight camera at the
# round start) and every fighter (close-up, same camera), Classic on top / Remaster below, 1600 px JPGs.
# Usage: tools/hd_proof.sh stages|fighters OUT_DIR [ids...]
cd "$(dirname "$0")/.."
G=/Applications/Godot.app/Contents/MacOS/Godot
PY=${PS_UPPY:-python3}
what=$1; out=$2; shift 2
mkdir -p "$out"
shot() {   # look out stage ids
  PS_LOOK=$1 timeout 150 $G --path game --resolution 1600x900 --fixed-fps 60 -s res://tests/look_shot.gd -- "$2" "$3" "$4" ${ANIM:-idle} > /dev/null 2>&1
}
pair() {   # name
  $PY -c "
from PIL import Image, ImageDraw
a=Image.open('/tmp/hdp_c.png').convert('RGB'); b=Image.open('/tmp/hdp_r.png').convert('RGB')
im=Image.new('RGB',(1600,1800)); im.paste(a,(0,0)); im.paste(b,(0,900)); d=ImageDraw.Draw(im)
for y,t in [(0,'CLASSIC'),(900,'REMASTER')]: d.rectangle([0,y,150,y+36],fill=(0,0,0)); d.text((12,y+10),t,fill=(255,255,255))
im.save('$out/$1.jpg', quality=90)"
}
if [ "$what" = stages ]; then
  ids=("$@"); [ ${#ids[@]} -eq 0 ] && ids=(stg00 stg10 stg20 stg30 stg40 stg50 stg60 stg70 stg80 stg90 stga0)
  for st in "${ids[@]}"; do
    # the game's own fight camera at the round start (CPU vs CPU, tests/shot.gd), same frame for both looks
    w=${WAIT:-420}; case $st in stg40) w=150;; stg70|stg80) w=600;; esac   # frames where the camera isn't behind a pipe/pillar
    for lk in classic remaster; do
      PS_SEED=7 PS_LOOK=$lk PS_STAGE=$st PS_CHARS=falcon,ryoma timeout 200 $G --path game --resolution 1600x900 --fixed-fps 60 \
        -s res://tests/shot.gd -- fight /tmp/hdp_${lk:0:1}.png $w > /dev/null 2>&1
    done
    pair $st
    echo "stage $st -> $out/$st.jpg"
  done
else
  ids=("$@"); [ ${#ids[@]} -eq 0 ] && ids=(falcon ryoma wangtang jack ayame gunrock galuda rouge kraken valgas finalvalgas)
  for f in "${ids[@]}"; do
    export PS_CENTER=4.0,2.6 PS_CAM=${CAM:-1.9,1.45,30,0} PS_LOOKY=${LOOKY:-1.15} PS_YAW=${YAW:-35}
    shot classic /tmp/hdp_c.png stg00 $f; shot remaster /tmp/hdp_r.png stg00 $f; pair $f
    echo "fighter $f -> $out/$f.jpg"
  done
fi
