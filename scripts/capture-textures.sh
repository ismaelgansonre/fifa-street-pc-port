#!/bin/zsh
# Capture des textures reelles pour texview.
# Usage : zsh scripts/capture-textures.sh [variante]
#   Cree la variante depuis le SDK fraichement construit si absente,
#   puis lance le jeu avec --vulkan_dump_textures vers dist/texdump.
#   Aller au Match Setup (ou plus loin), quitter, puis :
#     ./dist/tools/texview dist/texdump
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:-texdump-v1}"
if [[ ! -d "$REPO/dist/render-tests/$VARIANT" ]]; then
  python3 "$REPO/scripts/prepare-render-test.py" "$VARIANT"
fi
mkdir -p "$REPO/dist/texdump"
RUNTIME="$REPO/dist/render-tests/$VARIANT/runtime"
cd "$RUNTIME"
export DYLD_LIBRARY_PATH="$PWD"
exec ./fifastreet --no-fullscreen --resolution 1280x720 \
  --writable_code_segments \
  --game_data_root "$REPO/dist/GameData" \
  --execute_unclipped_draw_vs_on_cpu \
  --vulkan_dump_textures="$REPO/dist/texdump" \
  --mnk_mode "$@"
