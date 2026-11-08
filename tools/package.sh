#!/bin/bash
# Builds the Windows release: exports the game, adds server launchers + docs, zips it.
# Usage: tools/package.sh   (needs Godot 4.4.1 + Windows export templates)
set -e
cd "$(dirname "$0")/.."
OUT=build/BREACHLINE
rm -rf "$OUT" && mkdir -p "$OUT" release
godot --headless --path . --import >/dev/null 2>&1 || true
godot --headless --path . --export-release "Windows Desktop" "$OUT/BREACHLINE.exe"

cat > "$OUT/Start Dedicated Server.bat" <<'BAT'
@echo off
title BREACHLINE Dedicated Server
cd /d "%~dp0"
echo Starting BREACHLINE dedicated server... (settings: server.cfg)
BREACHLINE.console.exe --headless -- --server
pause
BAT
cat > "$OUT/Start Master Server.bat" <<'BAT'
@echo off
title BREACHLINE Master Server
cd /d "%~dp0"
echo Starting BREACHLINE master server on UDP 27900...
BREACHLINE.console.exe --headless -- --master
pause
BAT
sed -n '/^const SERVER_CFG_DEFAULT := """/,/^"""/p' scripts/main.gd | sed '1d;$d' > "$OUT/server.cfg"
cp docs/PLAYER_README.txt "$OUT/README.txt"
# Windows line endings for text files
for f in "$OUT"/*.bat "$OUT/server.cfg" "$OUT/README.txt"; do sed -i 's/$/\r/' "$f"; done
rm -f release/BREACHLINE-windows.zip
(cd build && zip -q -9 -r ../release/BREACHLINE-windows.zip BREACHLINE)
ls -la release/BREACHLINE-windows.zip
