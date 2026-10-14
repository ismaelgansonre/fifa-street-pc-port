#!/bin/zsh
# Pipeline complet : codegen → configure → build (macOS, SDK ReXGlue prébuildé immuable).
# Usage : zsh scripts/build-macos.sh   (depuis la racine du repo)
# Journal : dist/logs/build-macos.log
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$REPO/ReXGlue"
LOGDIR="$REPO/dist/logs"
mkdir -p "$LOGDIR"
cd "$REPO" || exit 1

echo "=== [$(date +%H:%M:%S)] PHASE 1/4: codegen (analyse + génération C++) ==="
"$SDK/bin/rexglue" codegen --progress_log_frequency 2000
_rc=$?
echo "codegen exit=$_rc"
if [ $_rc -ne 0 ]; then echo "ABORT: codegen failed"; exit 1; fi

echo "=== [$(date +%H:%M:%S)] PHASE 2/4: cmake configure (Ninja + ccache) ==="
cmake -G Ninja -S "$REPO" -B "$REPO/build" \
  -DCMAKE_PREFIX_PATH="$SDK" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache 2>&1 | tail -12
_rc=${pipestatus[1]}
echo "configure exit=$_rc"
if [ $_rc -ne 0 ]; then echo "ABORT: configure failed"; exit 1; fi

echo "=== [$(date +%H:%M:%S)] PHASE 3/4: build (-j8, TU register à -O0/-fno-global-isel) ==="
cmake --build "$REPO/build" --parallel 8 2>&1 | tail -50
_rc=${pipestatus[1]}
echo "build exit=$_rc"

echo "=== [$(date +%H:%M:%S)] PHASE 4/4: artefacts ==="
ls -la "$REPO/build/" | grep -vE "^total|CMakeFiles|\.ninja|cmake_install|rules" | head -20
