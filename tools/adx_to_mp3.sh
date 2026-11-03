#!/bin/bash
# ADX (from the disc) -> MP3 trimmed at the loop end + loops.json (loop_offset seconds) for Godot.
src=$1; out=$2; mkdir -p "$out"; echo "{" > "$out/loops.json"; first=1
for f in "$src"/*.ADX; do
  b=$(basename "$f" .ADX)
  meta=$(vgmstream-cli -m "$f")
  rate=$(echo "$meta" | awk '/sample rate/{print $3}')
  ls=$(echo "$meta" | awk '/loop start:/{print $3}'); le=$(echo "$meta" | awk '/loop end:/{print $3}')
  vgmstream-cli -i -o ${TMPDIR:-/tmp}/adx_$b.wav "$f" >/dev/null 2>&1
  if [ -n "$le" ]; then
    ffmpeg -loglevel error -y -i ${TMPDIR:-/tmp}/adx_$b.wav -af "atrim=end_sample=$le" -c:a libmp3lame -q:a 2 "$out/$b.mp3"
    [ $first = 1 ] || echo "," >> "$out/loops.json"; first=0
    printf '"%s": %.6f' "$b" "$(echo "scale=6; $ls/$rate" | bc)" >> "$out/loops.json"
  else
    ffmpeg -loglevel error -y -i ${TMPDIR:-/tmp}/adx_$b.wav -c:a libmp3lame -q:a 2 "$out/$b.mp3"
  fi
  rm -f ${TMPDIR:-/tmp}/adx_$b.wav
done
echo "}" >> "$out/loops.json"; echo ADX-DONE
