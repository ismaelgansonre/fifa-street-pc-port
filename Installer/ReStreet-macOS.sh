#!/bin/bash
# ReStreet-macOS.sh - Minimal macOS launcher for ReStreet (FIFA Street 2012).
#
# This is the macOS counterpart of FifaStreetLauncher.exe (which is
# WinForms / net8.0-windows and cannot run on macOS). It applies graphics
# profiles and options as --cvar=value command-line overrides: the CLI
# outranks the bundled fifastreet.toml (see cvar.cpp Init/LoadConfig), so
# the .app bundle stays pristine and its code signature intact.
#
# Layouts supported (auto-detected from this script's location):
#   ReStreet.app/Contents/MacOS/ReStreet   (packaged: binary + dylibs beside
#                                           it, vulkan/ subtree, toml in
#                                           ../Resources/, GameData wired at
#                                           Contents/GameData by Install-macOS.sh)
#   <repo>/Installer/ReStreet-macOS.sh     (dev: expects BUILD_DIR below)
#
# Usage:
#   ReStreet-macOS.sh [--play] [--profile balanced|quality|performance]
#     [--resolution WxH] [--fullscreen|--windowed] [--vsync on|off]
#     [--readback full|some|fast|none] [--show-config] [--dry-run]
#
# Examples:
#   ReStreet-macOS.sh --play
#   ReStreet-macOS.sh --profile quality --resolution 2560x1440 --play
#   ReStreet-macOS.sh --profile performance --windowed --dry-run

set -uo pipefail

SUPPORT="$HOME/Library/Application Support/ReStreet"
SAVED="$SUPPORT/launcher.conf"

PROFILE="balanced"
RES_W=""; RES_H=""
FULLSCREEN=""; VSYNC=""
READBACK=""
KEYBOARD="true"
DRY_RUN=0; SHOW_CONFIG=0; PLAY=0

usage() { sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; }

# Saved defaults (KEY=VALUE, written by --save below via explicit opt-in).
if [ -f "$SAVED" ]; then
  # shellcheck disable=SC1090
  . "$SAVED"
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --play) PLAY=1; shift ;;
    --profile) PROFILE="${2:?--profile needs balanced|quality|performance}"; shift 2 ;;
    --resolution) IFS=x read -r RES_W RES_H <<< "${2:?--resolution needs WxH}"; shift 2 ;;
    --fullscreen) FULLSCREEN=true; shift ;;
    --windowed) FULLSCREEN=false; shift ;;
    --vsync) VSYNC="${2:?--vsync needs on|off}"; shift 2 ;;
    --readback) READBACK="${2:?--readback needs full|some|fast|none}"; shift 2 ;;
    --keyboard) KEYBOARD=true; shift ;;
    --no-keyboard) KEYBOARD=false; shift ;;
    --show-config) SHOW_CONFIG=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --save) SAVE_DEFAULTS=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1 (see --help)" >&2; exit 1 ;;
  esac
done

# --- Locate the game binary -------------------------------------------------
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -x "$SELF_DIR/fifastreet" ]; then
  EXE="$SELF_DIR/fifastreet"                       # packaged .app or build dir
elif [ -x "$SELF_DIR/../MacOS/fifastreet" ]; then
  EXE="$SELF_DIR/../MacOS/fifastreet"
else
  # Dev fallback: the from-source build tree.
  REPO="$(cd "$SELF_DIR/.." && pwd)"
  BUILD="$REPO/dist/mac-build/FifaStreetRex/out/build/mac-arm64-release"
  EXE="$BUILD/fifastreet"
fi
[ -x "$EXE" ] || { echo "fifastreet binary not found (looked beside $0 and in dist/mac-build)" >&2; exit 1; }
EXE_DIR="$(dirname "$EXE")"

# --- Profiles (macOS-validated defaults) ------------------------------------
# Balanced/Quality/Performance mirror the Windows launcher's intent, with the
# macOS-specific corrections from STATUS.md: windowed (fullscreen presents
# black), fsi render-target path, occlusion queries off (unreliable on
# MoltenVK), async shader compilation on.
case "$PROFILE" in
  balanced)
    RES_W="${RES_W:-1280}"; RES_H="${RES_H:-720}"
    FULLSCREEN="${FULLSCREEN:-false}"; VSYNC="${VSYNC:-off}"
    READBACK="${READBACK:-fast}"
    SCALE=1; MSAA=false; POST=none ;;
  quality)
    RES_W="${RES_W:-1920}"; RES_H="${RES_H:-1080}"
    FULLSCREEN="${FULLSCREEN:-false}"; VSYNC="${VSYNC:-off}"
    READBACK="${READBACK:-some}"
    SCALE=1; MSAA=false; POST=none ;;
  performance)
    RES_W="${RES_W:-1280}"; RES_H="${RES_H:-720}"
    FULLSCREEN="${FULLSCREEN:-false}"; VSYNC="${VSYNC:-off}"
    READBACK="${READBACK:-fast}"
    SCALE=1; MSAA=false; POST=none ;;
  *) echo "unknown profile: $PROFILE" >&2; exit 1 ;;
esac
# --- Build the CLI overrides (outrank fifastreet.toml) -----------------------
ARGS=(
  "--render_target_path_vulkan=fsi"
  "--readback_resolve=$READBACK"
  "--readback_memexport=true"
  "--readback_memexport_fast=true"
  "--occlusion_query_enable=false"
  "--async_shader_compilation=true"
  "--video_mode_width=$RES_W"
  "--video_mode_height=$RES_H"
  "--resolution_scale=$SCALE"
  "--draw_resolution_scale_x=$SCALE"
  "--draw_resolution_scale_y=$SCALE"
  "--swap_post_effect=$POST"
)
if [ "$FULLSCREEN" = "true" ]; then ARGS+=("--fullscreen"); else ARGS+=("--no-fullscreen"); fi
if [ "$VSYNC" = "on" ]; then ARGS+=("--vsync"); else ARGS+=("--no-vsync"); fi
if [ "$MSAA" = "true" ]; then ARGS+=("--native_2x_msaa"); else ARGS+=("--no-native_2x_msaa"); fi
# Keyboard/mouse -> controller emulation (MNK driver). ON by default on macOS:
# most Macs have no Xbox pad plugged in, and the guest boots with no input
# otherwise. Disable with --no-keyboard when a real pad is used.
if [ "$KEYBOARD" = "true" ]; then ARGS+=("--mnk_mode"); else ARGS+=("--no-mnk_mode"); fi

if [ "${SAVE_DEFAULTS:-0}" -eq 1 ]; then
  mkdir -p "$SUPPORT"
  cat > "$SAVED" <<EOF
# ReStreet macOS launcher defaults (written $(date '+%Y-%m-%d %H:%M')).
PROFILE="$PROFILE"
RES_W="$RES_W"; RES_H="$RES_H"
FULLSCREEN="$FULLSCREEN"; VSYNC="$VSYNC"
READBACK="$READBACK"
EOF
  echo "saved defaults to $SAVED"
fi

if [ "$SHOW_CONFIG" -eq 1 ] || [ "$DRY_RUN" -eq 1 ]; then
  echo "binary : $EXE"
  echo "profile: $PROFILE (${RES_W}x${RES_H}, fullscreen=$FULLSCREEN, vsync=$VSYNC, readback=$READBACK, scale=${SCALE}x)"
  echo "args   : ${ARGS[*]}"
fi

if [ "$DRY_RUN" -eq 1 ]; then exit 0; fi

# GameData sanity check (wired by Install-macOS.sh at Contents/GameData).
if [ ! -f "$EXE_DIR/GameData/default.xex" ] && \
   [ ! -f "$EXE_DIR/../GameData/default.xex" ] && \
   [ ! -f "$EXE_DIR/../Resources/GameData/default.xex" ]; then
  echo "warning: no GameData found near the bundle - run Installer/Install-macOS.sh first" >&2
fi

# Run from the support dir so logs and caches stay out of the bundle.
# Fall back to a temp dir when the support dir cannot be created
# (restricted environments, first-run permission issues).
RUNDIR="$SUPPORT"
mkdir -p "$RUNDIR" 2>/dev/null || RUNDIR="$(mktemp -d -t restreet 2>/dev/null || echo "$EXE_DIR")"
cd "$RUNDIR" || exit 1
# Disable Retina 2x backing: without this, a 1280x720 window gets a
# 2560x1440 swapchain (contents scale 2.0) and the GPU pays full 1440p.
# With high-DPI off, 1280x720 = vraie 720p, 1920x1080 = vraie 1080p.
export SDL_VIDEO_HIGHDPI_DISABLED=1
export SDL_HINT_VIDEO_HIGHDPI_DISABLED=1
# Redirect shader/pipeline caches into the support dir: under sandboxed or
# restricted launches ~/.local/share may not be writable, and the run then
# stalls ~20 s recompiling shaders every boot with
# "persistent shader storage will be disabled".
export XDG_CACHE_HOME="$RUNDIR/cache"
mkdir -p "$XDG_CACHE_HOME" 2>/dev/null || true
exec "$EXE" "${ARGS[@]}"
