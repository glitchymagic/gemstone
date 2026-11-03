#!/bin/bash
# Fresh real-model screenshots on the Mac (pass 3): one fight per fighter on his/her home stage (CPU vs CPU, shot at
# a hit) + one per stage at the round start, 1920x1080, High quality. Prints the frame time of each run.
# Usage: shots.sh [fighters|stages]   (default: both)
cd ./
G=/Applications/Godot.app/Contents/MacOS/Godot
O=docs/shots
mkdir -p $O/fighters $O/stages
ids=(falcon ryoma wangtang jack gunrock galuda ayame rouge kraken valgas finalvalgas)
stg=(stg00 stg10 stg20 stg30 stg40 stg50 stg60 stg70 stg80 stg90 stga0)
n=${#ids[@]}
for ((k=0; k<n; k++)); do
  [ "$1" = stages ] && break
  a=${ids[$k]}; b=${ids[$(( (k+1) % (n-1) ))]}; [ "$a" = finalvalgas ] && b=falcon
  want=hit; [ "$a" = finalvalgas ] && want=""
  PS_STAGE=${stg[$k]} PS_CHARS=$a,$b timeout 300 $G --path game --resolution 1920x1080 -s res://tests/shot.gd -- fight $PWD/$O/fighters/$(printf %02d $k)_$a.png 400 $want 2>&1 | grep -E "^SHOT|^RENDER" | sed "s#^#$a: #"
done
[ "$1" = fighters ] && exit 0
for ((k=0; k<n; k++)); do
  s=${stg[$k]}; a=${ids[$k]}; b=falcon; [ "$a" = falcon ] && b=ryoma
  PS_STAGE=$s PS_CHARS=$b,$a timeout 300 $G --path game --resolution 1920x1080 -s res://tests/shot.gd -- fight $PWD/$O/stages/$s.png 150 2>&1 | grep -E "^SHOT|^RENDER" | sed "s#^#$s: #"
done
