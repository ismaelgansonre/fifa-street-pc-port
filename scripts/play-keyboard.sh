#!/bin/zsh
# Lancement test clavier (J4) — sans manette.
# Usage : zsh scripts/play-keyboard.sh [variante] [-- <flags jeu suppl.>...]
#   variante : nom sous dist/render-tests/ (défaut : vulkan-fixes-v1).
#   Seed config/fifastreet-mnk.toml vers <variante>/runtime/fifastreet.toml
#   (création si absent, sinon force mnk_mode=true —
#   le toml surcharge la ligne de commande, le flag seul ne suffirait pas).
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
VARIANT="${1:-vulkan-fixes-v1}"
if [[ "$VARIANT" == "--" ]]; then VARIANT="vulkan-fixes-v1"; fi
RUNTIME="$REPO/dist/render-tests/$VARIANT/runtime"
if [[ ! -d "$RUNTIME" ]]; then
  echo "variante introuvable : $RUNTIME" >&2; exit 1
fi
SEED="$REPO/config/fifastreet-mnk.toml"
TOML="$RUNTIME/fifastreet.toml"
if [[ ! -f "$TOML" ]]; then
  cp "$SEED" "$TOML"
  echo "seed clavier copié vers $TOML"
else
  python3 - "$TOML" <<'EOF'
import sys, re
p = sys.argv[1]
s = open(p).read()
if re.search(r'(?m)^mnk_mode\s*=', s):
    s = re.sub(r'(?m)^mnk_mode\s*=.*$', 'mnk_mode = true', s)
else:
    s = s.rstrip('\n') + '\nmnk_mode = true\n'
open(p, 'w').write(s)
EOF
  echo "mnk_mode=true forcé dans $TOML"
fi
shift 2>/dev/null || true
if [[ "${1:-}" == "--" ]]; then shift; fi
cd "$RUNTIME"
export DYLD_LIBRARY_PATH="$PWD"
exec ./fifastreet --no-fullscreen --resolution 1280x720 \
  --writable_code_segments \
  --game_data_root "$REPO/dist/GameData" \
  --mnk_mode "$@"
