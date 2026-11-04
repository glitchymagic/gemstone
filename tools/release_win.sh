#!/bin/bash
# Windows bundle (no game data in it): Godot 4.7.2 + embeddable Python 3.11 with the importer's wheels + ffmpeg +
# vgmstream + this checkout, and Gemstone.bat. The player unzips it, runs Gemstone.bat, points the import screen at
# their own disc dump, and plays. Runs on macOS/Linux (pip downloads the win_amd64 wheels).
# Usage: tools/release_win.sh OUT_DIR        -> OUT_DIR/gemstone-win64.zip
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out dir}; mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
B="$OUT/gemstone-win64"; rm -rf "$B"; mkdir -p "$B"/{godot,python,bin}
DL="$OUT/downloads"; mkdir -p "$DL"
PY=${PS_PY:-python3}
GODOT_V=4.7.2-stable
get() { [ -s "$DL/$2" ] || curl -fsSL -o "$DL/$2" "$1"; }

# 1. Godot (the editor build: it imports the player's assets on first run, then runs the game)
get "https://github.com/godotengine/godot-builds/releases/download/$GODOT_V/Godot_v${GODOT_V}_win64.exe.zip" godot.zip
unzip -qo "$DL/godot.zip" -d "$B/godot"

# 2. Python 3.11 embeddable + the importer's wheels (CPU torch: the upscalers run on the CPU on Windows)
get "https://www.python.org/ftp/python/3.11.9/python-3.11.9-embed-amd64.zip" python.zip
unzip -qo "$DL/python.zip" -d "$B/python"
sed -i.bak 's/^#import site/import site/' "$B"/python/python311._pth && rm -f "$B"/python/python311._pth.bak
echo 'Lib/site-packages' >> "$B"/python/python311._pth
$PY -m pip install --quiet --target "$B/python/Lib/site-packages" --platform win_amd64 --python-version 3.11 \
    --only-binary=:all: --extra-index-url https://download.pytorch.org/whl/cpu -r importer/requirements.txt

# (torch also needs the Microsoft VC++ runtime, msvcp140.dll: Gemstone.bat checks for it and links the installer)
# 3. ffmpeg + vgmstream-cli (music / announcer decode)
get "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl.zip" ffmpeg.zip
unzip -qo -j "$DL/ffmpeg.zip" '*/bin/ffmpeg.exe' -d "$B/bin"
get "https://github.com/vgmstream/vgmstream/releases/latest/download/vgmstream-win64.zip" vgmstream.zip
unzip -qo "$DL/vgmstream.zip" -d "$B/bin"

# 4. this checkout (tracked files only: no disc data can be in it, tools/audit_clean.py checks that)
git archive --format=tar HEAD | tar -x -C "$B"
cat > "$B/Gemstone.bat" <<'BAT'
@echo off
rem Gemstone: first run shows the import screen (point it at your own Power Stone disc dump), then the game.
set "HERE=%~dp0"
set "PATH=%HERE%bin;%HERE%python;%PATH%"
set "PS_PYTHON=%HERE%python\python.exe"
if not exist "%SystemRoot%\System32\msvcp140.dll" (
  echo The importer needs the Microsoft Visual C++ Redistributable ^(x64^):
  echo https://aka.ms/vs/17/release/vc_redist.x64.exe
  echo Install it, then run Gemstone.bat again.
  pause
  exit /b 1
)
rem first start: Godot indexes the game's own scripts once (nothing from the disc yet) so the import screen can open
if not exist "%HERE%game\.godot\global_script_class_cache.cfg" (
  echo First start: preparing the game files, one moment...
  "%HERE%godot\Godot_v4.7.2-stable_win64_console.exe" --headless --path "%HERE%game" --import
)
start "" "%HERE%godot\Godot_v4.7.2-stable_win64.exe" --path "%HERE%game"
BAT
cat > "$B/IMPORT_CLI.bat" <<'BAT'
@echo off
rem Power users: run the importer by hand.  IMPORT_CLI.bat "D:\dumps\Power Stone (USA).gdi"
set "HERE=%~dp0"
set "PATH=%HERE%bin;%HERE%python;%PATH%"
"%HERE%python\python.exe" "%HERE%importer\psimport.py" %* --godot "%HERE%godot\Godot_v4.7.2-stable_win64_console.exe"
BAT
cat > "$B/THIRD_PARTY.txt" <<'TXT'
Bundled, unmodified, under their own licenses:
- Godot Engine 4.7.2 (MIT) https://godotengine.org
- Python 3.11.9 embeddable (PSF License) https://www.python.org, with numpy, pillow, scipy, torch (CPU), torchvision,
  spandrel and their dependencies (see each package's metadata in python/Lib/site-packages)
- FFmpeg (LGPL build, BtbN/FFmpeg-Builds) https://ffmpeg.org
- vgmstream (ISC-style license) https://github.com/vgmstream/vgmstream
No part of Power Stone is included. You need your own copy of the game.
TXT
(cd "$OUT" && rm -f gemstone-win64.zip && zip -qr gemstone-win64.zip gemstone-win64)
ls -la "$OUT/gemstone-win64.zip"
