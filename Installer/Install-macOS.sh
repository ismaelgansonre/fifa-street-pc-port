#!/bin/bash
# Install-macOS.sh - Provide game data to ReStreet.app on macOS.
#
# macOS counterpart of the FifaStreetSetupTool installer flow (WinForms):
# it takes YOUR OWN FIFA Street (2012) Xbox 360 copy - either an ISO or an
# already-extracted GameData folder (e.g. from a CrossOver bottle) - and
# wires it to a packaged ReStreet.app plus a canonical store at
# ~/Library/Application Support/ReStreet/GameData.
#
# Usage:
#   Installer/Install-macOS.sh --app <ReStreet.app> (--iso <file> | --gamedata <dir>)
#     [--copy|--link] [--force]
#
#   --copy (default) duplicates the data into Application Support (the app
#     keeps working if the source disappears). --link symlinks instead
#     (no extra disk use, but the source must stay mounted).
#
# ISO extraction needs the extract-xiso tool (XboxDev/extract-xiso,
# cross-platform): place the built binary at Installer/tools/extract-xiso
# or somewhere on PATH. Without it, only --gamedata works.

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP=""; ISO=""; GAMEDATA=""; MODE="copy"; FORCE=0
TMP=""; SRC_IS_TMP=0
STORE="$HOME/Library/Application Support/ReStreet/GameData"

while [ $# -gt 0 ]; do
  case "$1" in
    --app) APP="${2:?--app needs ReStreet.app}"; shift 2 ;;
    --iso) ISO="${2:?--iso needs a file}"; shift 2 ;;
    --gamedata) GAMEDATA="${2:?--gamedata needs a directory}"; shift 2 ;;
    --copy) MODE="copy"; shift ;;
    --link) MODE="link"; shift ;;
    --force) FORCE=1; shift ;;
    --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

[ -n "$APP" ] || { echo "missing --app (see --help)" >&2; exit 1; }
[ -d "$APP/Contents/MacOS" ] || { echo "not a packaged app: $APP (run Package-macOS.sh first)" >&2; exit 1; }
[ -n "$ISO$GAMEDATA" ] || { echo "need --iso or --gamedata (see --help)" >&2; exit 1; }
[ -z "$ISO" ] || [ -z "$GAMEDATA" ] || { echo "use only one of --iso / --gamedata" >&2; exit 1; }

check_modules() { # check_modules <dir>
  local dir="$1" missing=0
  [ -f "$dir/default.xex" ] || { echo "  missing default.xex"; missing=1; }
  [ -f "$dir/fifadllzf.xex.dll" ] || { echo "  missing fifadllzf.xex.dll"; missing=1; }
  [ -f "$dir/dlc/dlc_FootballCompEng/dlc/FootballCompEng/FootballCompEngzf.xex.dll" ] \
    || { echo "  missing FootballCompEng DLC module"; missing=1; }
  return "$missing"
}

if [ -n "$ISO" ]; then
  [ -f "$ISO" ] || { echo "ISO not found: $ISO" >&2; exit 1; }
  XISO=""
  for candidate in "$REPO/Installer/tools/extract-xiso" "$(command -v extract-xiso || true)"; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && XISO="$candidate" && break
  done
  [ -n "$XISO" ] || {
    echo "no extract-xiso tool found." >&2
    echo "Build it from https://github.com/XboxDev/extract-xiso and place the" >&2
    echo "binary at Installer/tools/extract-xiso (or on PATH), then re-run." >&2
    echo "Alternatively extract on Windows once and pass the folder via --gamedata." >&2
    exit 1
  }
  echo "extracting ISO with $XISO ..."
  TMP="$STORE.tmp-$$"
  rm -rf "$TMP"; mkdir -p "$TMP"
  "$XISO" -x -d "$TMP" "$ISO" || { echo "extraction failed" >&2; rm -rf "$TMP"; exit 1; }
  echo "checking extracted modules:"
  check_modules "$TMP" || { echo "extracted tree is not a FIFA Street GameData" >&2; rm -rf "$TMP"; exit 1; }
  SRC="$TMP"; SRC_IS_TMP=1
else
  [ -d "$GAMEDATA" ] || { echo "GameData dir not found: $GAMEDATA" >&2; exit 1; }
  echo "checking modules in $GAMEDATA:"
  check_modules "$GAMEDATA" || exit 1
  SRC="$GAMEDATA"
fi

# --- Populate the canonical store ----------------------------------------------
if [ -e "$STORE" ] || [ -L "$STORE" ]; then
  [ "$FORCE" -eq 1 ] || { echo "$STORE exists (re-run with --force to replace)" >&2; [ "$SRC_IS_TMP" -eq 1 ] && rm -rf "$SRC"; exit 1; }
  rm -rf "$STORE"
fi
mkdir -p "$(dirname "$STORE")"
if [ "$MODE" = "link" ]; then
  ln -s "$SRC" "$STORE"
  echo "linked: $STORE -> $SRC"
else
  mkdir -p "$STORE"
  # ditto preserves resource forks/xattrs better than cp on macOS.
  ditto "$SRC/" "$STORE/" || { echo "copy failed" >&2; exit 1; }
  [ -n "$ISO" ] && rm -rf "$SRC"   # temp extraction tree, no longer needed
  echo "copied to $STORE"
fi

# --- Wire the bundle (OnConfigurePaths finds Contents/GameData) -----------------
LINK="$APP/Contents/GameData"
rm -f "$LINK"
ln -s "$STORE" "$LINK"
echo "wired: $LINK -> $STORE"

# --- Re-sign after wiring (ad-hoc; local builds) ----------------------------------
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - "$APP/Contents/MacOS/fifastreet" >/dev/null 2>&1 || true
  echo "re-signed (ad-hoc)"
  echo "If macOS quarantines the app on first launch, run once:"
  echo "  xattr -dr com.apple.quarantine \"$APP\""
fi

echo "=== done: open $APP or run $APP/Contents/MacOS/ReStreet --play ==="
