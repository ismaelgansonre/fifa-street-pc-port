#!/bin/zsh
# Build texview (visionneuse .retex) + test du decodeur.
# Usage : zsh texview/build.sh
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$REPO/sdk-src"
OUT="$REPO/dist/tools"
mkdir -p "$OUT" /tmp/texharness/retex-test

echo "=== test decodeur (synthetique, sans jeu) ==="
clang++ -std=c++23 -I "$SDK/include" -I "$REPO/texview" \
  "$SDK/src/graphics/pipeline/texture/util.cpp" \
  "$SDK/src/graphics/pipeline/texture/info_formats.cpp" \
  "$SDK/src/core/math_gcc.cpp" \
  "$REPO/texview/decode.cpp" "$REPO/texview/test_decode.cpp" \
  -o /tmp/texharness/test_decode
/tmp/texharness/test_decode

echo "=== visionneuse SDL3 ==="
clang++ -std=c++23 -O2 -I "$SDK/include" -I "$REPO/texview" \
  -I "$SDK/thirdparty/sdl3/include" \
  "$SDK/src/graphics/pipeline/texture/util.cpp" \
  "$SDK/src/graphics/pipeline/texture/info_formats.cpp" \
  "$SDK/src/core/math_gcc.cpp" \
  "$REPO/texview/decode.cpp" "$REPO/texview/viewer.cpp" \
  "$SDK/out/mac-arm64/Release/libSDL3.a" \
  -framework Cocoa -framework IOKit -framework CoreVideo \
  -framework CoreAudio -framework AudioToolbox -framework AVFoundation \
  -framework Metal -framework GameController -framework CoreHaptics \
  -framework ForceFeedback -framework Carbon -framework QuartzCore \
  -framework UniformTypeIdentifiers \
  -o "$OUT/texview"
echo "binaire : $OUT/texview"
