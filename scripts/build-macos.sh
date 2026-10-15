#!/bin/zsh
# Pipeline : codegen → vérification → configure → build (SDK séparé dist/sdk/).
# Usage : zsh scripts/build-macos.sh   (depuis la racine du repo)
# Journal : dist/logs/build-macos.log
set -e
setopt pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$REPO/dist/sdk"
LOGDIR="$REPO/dist/logs"
mkdir -p "$LOGDIR"
cd "$REPO" || exit 1

if [[ ! -x "$SDK/bin/rexglue" ]]; then
    echo "ABORT: construire le SDK séparé avec zsh scripts/sdk-build-patched.sh" >&2
    exit 1
fi

# The upstream stamp hashes the SDK version, not our local codegen changes.
# Regenerate once per generator binary; retain the normal module cache later.
TOOL_STAMP="$LOGDIR/codegen-tool.sha256"
TOOL_HASH=$(shasum -a 256 "$SDK/bin/rexglue" | cut -d ' ' -f 1)
CODEGEN_ARGS=()
if [[ ! -f "$TOOL_STAMP" ]] || [[ "$(cat "$TOOL_STAMP")" != "$TOOL_HASH" ]]; then
    CODEGEN_ARGS+=(--ignore-stamp)
fi

echo "=== [$(date +%H:%M:%S)] PHASE 1/5: codegen (analyse + génération C++) ==="
"$SDK/bin/rexglue" codegen "$REPO/fifastreet_manifest.toml" "${CODEGEN_ARGS[@]}" --progress_log_frequency 2000
_rc=$?
echo "codegen exit=$_rc"
if [ $_rc -ne 0 ]; then echo "ABORT: codegen failed"; exit 1; fi
echo "$TOOL_HASH" > "$TOOL_STAMP"

echo "=== [$(date +%H:%M:%S)] PHASE 2/5: vérification du contrôle de flux ==="
python3 scripts/verify_direct_branches.py
python3 scripts/verify_ctr_region.py
python3 scripts/verify_allocation_region.py

echo "=== [$(date +%H:%M:%S)] PHASE 3/5: cmake configure (Ninja + ccache) ==="
cmake -G Ninja -S "$REPO" -B "$REPO/build" \
  -Urexglue_DIR -DREXSDK_DIR= \
  -DCMAKE_PREFIX_PATH="$SDK" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache 2>&1 | tail -12
_rc=${pipestatus[1]}
echo "configure exit=$_rc"
if [ $_rc -ne 0 ]; then echo "ABORT: configure failed"; exit 1; fi

echo "=== [$(date +%H:%M:%S)] PHASE 4/5: build (-j8, TU register à -O0/-fno-global-isel) ==="
cmake --build "$REPO/build" --parallel 8 2>&1 | tail -50
_rc=${pipestatus[1]}
echo "build exit=$_rc"

echo "=== [$(date +%H:%M:%S)] PHASE 5/5: artefacts ==="
ls -lh "$REPO/build/fifastreet" "$REPO/build/"*.dylib
