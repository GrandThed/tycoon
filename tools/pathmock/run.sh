#!/usr/bin/env bash
# Regenerate the Village path mock: geometry -> texture -> Blender renders -> growth strip.
# Usage: bash tools/pathmock/run.sh [views]   (views default: top,persp_front,persp_close,growth)
set -euo pipefail
cd "$(dirname "$0")/../.."
BLENDER="/c/Program Files/Blender Foundation/Blender 5.2/blender.exe"
BPY="/c/Program Files/Blender Foundation/Blender 5.2/5.2/python/bin/python.exe"
OUT="assets/testfit/out/Village/paths"
MESH="${PATHMOCK_MESH:-$OUT/pathmock_mesh.json}"
VIEWS="${1:-top,persp_front,persp_close,growth}"
mkdir -p "$OUT"
py tools/pathmock/pathgeom.py "$MESH" --grow "${PATHMOCK_GROW:-tentSmall}" --frames 6
"$BPY" tools/pathmock/texture.py "$OUT"
"$BLENDER" -b -P tools/pathmock/render.py -- --mesh "$MESH" --texture "$OUT/village_path.png" --out "$OUT" --views "$VIEWS" ${PATHMOCK_ARGS:-} 2>&1 | grep -E "pathmock|Error|Traceback" || true
if [[ "$VIEWS" == *growth* ]]; then py tools/pathmock/strip.py "$OUT"; fi
