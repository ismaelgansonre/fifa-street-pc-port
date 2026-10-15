#!/bin/zsh
# Build du SDK ReXGlue v0.10.0 (source officielle c94f5eb) + patches projet.
# Le SDK téléchargé ReXGlue/ reste INTACT : ce build s'installe dans dist/sdk/.
# Usage : zsh scripts/sdk-build-patched.sh
# Journal : dist/logs/sdk-build.log
set -e
setopt pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO/sdk-src"
LOGDIR="$REPO/dist/logs"
mkdir -p "$LOGDIR"
cd "$SRC" || exit 1

echo "=== [$(date +%H:%M:%S)] PHASE 1/4: sous-modules ==="
git submodule update --init --recursive --depth 1 2>&1 | tail -5
echo "submodules exit=$?"

echo "=== [$(date +%H:%M:%S)] PHASE 2/4: patches ==="
# NOTE (2026-10-15) : rexglue-v0.10.0-vmsum3fp128-mask a ete RETIRE.
# Le masque d'origine 0xEF est deja correct : pour simde_mm_dp_ps le nibble haut
# selectionne les sources et le nibble bas les destinations, donc 0xEF = dot3 des
# lanes 1,2,3 (= guest x,y,z, stockage inversé) diffuse sur les 4 lanes.
# Le "fix" 0x7F sommait les lanes 0..2 (= guest w,z,y) et ecrasait host lane 3
# (= guest element 0) -> geometrie aplatie / joueurs invisibles.
# Verifie empiriquement (simde sur arm64) et contre la reference Xenia
# (InstrEmit_vmsum3fp128 = DotProduct3 + Splat).
for patch in rexglue-v0.10.0-image-overlap-fix rexglue-v0.10.0-writable-code-segments rexglue-v0.10.0-shared-control-flow rexglue-v0.10.0-vulkan-3d-textures rexglue-v0.10.0-vector-pack-fix rexglue-v0.10.0-present-interval-cap rexglue-v0.10.0-vulkan-texture-pipeline-fixes rexglue-v0.10.0-waitmultiple-backoff rexglue-v0.10.0-vulkan-presenter-pipeline-fix rexglue-v0.10.0-menu-frame-trace rexglue-v0.10.0-readback-some-adaptive; do
    if git apply --check "$REPO/patches/$patch.patch" 2>/dev/null; then
        git apply "$REPO/patches/$patch.patch" && echo "$patch applique"
    elif git apply --reverse --check "$REPO/patches/$patch.patch" 2>/dev/null; then
        echo "$patch deja applique"
    else
        echo "ABORT: $patch incompatible avec sdk-src" >&2
        exit 1
    fi
done
git diff --stat | tail -3

echo "=== [$(date +%H:%M:%S)] PHASE 3/4: build (preset mac-arm64, -j8) ==="
cmake --preset mac-arm64 2>&1 | tail -6
cmake --build out/build/mac-arm64 --config Release --target all:Release --parallel 8 2>&1 | tail -15
_rc=$?
echo "build exit=$_rc"
if [ $_rc -ne 0 ]; then echo "ABORT: build SDK echoue"; exit 1; fi

echo "=== [$(date +%H:%M:%S)] PHASE 4/4: install vers dist/sdk ==="
cmake --install out/build/mac-arm64 --config Release --prefix "$REPO/dist/sdk" 2>&1 | tail -5
echo "install exit=$?"
ls "$REPO/dist/sdk/lib/" 2>/dev/null | head -8
