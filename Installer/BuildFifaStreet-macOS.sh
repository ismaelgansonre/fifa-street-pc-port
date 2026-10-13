#!/bin/bash
# BuildFifaStreet-macOS.sh - ReStreet from-source build for macOS (Apple Silicon).
#
# macOS counterpart of BuildFifaStreet.ps1 -SourceBuild. Prepares the pinned
# ReXGlue SDK (main project patch + macOS addendum), builds it with the Vulkan
# backend (rendered through MoltenVK on macOS), recompiles the game from your
# own extracted GameData and links the host executable.
#
# Usage:
#   Installer/BuildFifaStreet-macOS.sh --gamedata <path> [options]
#
# Options:
#   --gamedata <path>  Extracted game folder containing default.xex,
#                      fifadllzf.xex.dll and the FootballCompEng DLC module.
#                      Required on the first run; remembered in the workspace
#                      afterwards.
#   --jobs <N>         Parallel compile jobs (default 6).
#   --smoke-test       After a successful build, run the game for ~45 s and
#                      capture a screenshot under dist/mac-build/logs/.
#   --help             Show this help.
#
# The build workspace lives in dist/mac-build/FifaStreetRex and is fully
# resumable: re-run the same command after fixing a failure. Never delete
# dist/mac-build/FifaStreetRex/out/build - a wipe forces a full recompile.
#
# Prerequisites: Xcode Command Line Tools (clang), CMake 3.25+, Ninja, Git,
# and the MoltenVK runtime bundled by the SDK (no separate install needed).
# A first full build takes roughly 30-60 minutes; the two generated metadata
# files of the fifadllzf module dominate that time and are compiled -O1
# automatically (see Installer/recomp-template/CMakeLists.txt).

set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SDK_REV="c94f5ebdcb3c9d1a460ca48e04f9758448f8d518"   # ReXGlue v0.10.0
WORK="$REPO/dist/mac-build"
PROJ="$WORK/FifaStreetRex"
LOGDIR="$WORK/logs"
LOG="$LOGDIR/build-macos.log"
LOCK="$WORK/.macbuild.lock"
SDK="$REPO/ReXGlue"

GAMEDATA=""
JOBS=6
SMOKE=0

usage() {
  cat <<'EOF'
BuildFifaStreet-macOS.sh - ReStreet from-source build for macOS (Apple Silicon).

Usage:
  Installer/BuildFifaStreet-macOS.sh --gamedata <path> [options]

Options:
  --gamedata <path>  Extracted game folder containing default.xex,
                     fifadllzf.xex.dll and the FootballCompEng DLC module.
                     Required on the first run; remembered in the workspace
                     afterwards.
  --jobs <N>         Parallel compile jobs (default 6).
  --smoke-test       After a successful build, run the game for ~45 s and
                     capture a screenshot under dist/mac-build/logs/.
  --help             Show this help.

The build workspace lives in dist/mac-build/FifaStreetRex and is fully
resumable: re-run the same command after fixing a failure. Never delete
dist/mac-build/FifaStreetRex/out/build - a wipe forces a full recompile.
EOF
}

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }
die() { log "FATAL: $*"; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --gamedata) GAMEDATA="${2:?--gamedata needs a path}"; shift 2 ;;
    --jobs) JOBS="${2:?--jobs needs a number}"; shift 2 ;;
    --smoke-test) SMOKE=1; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

mkdir -p "$LOGDIR"

if ! mkdir "$LOCK" 2>/dev/null; then
  oldpid="$(cat "$LOCK/pid" 2>/dev/null || true)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    echo "build already running (pid $oldpid) - exiting"; exit 0
  fi
  rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || { echo "lock failed"; exit 0; }
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

log "=== ReStreet macOS build start (pid $$) ==="
log "repo: $REPO"

# --- Stage 0: preflight -----------------------------------------------------
[ "$(uname -s)" = "Darwin" ] || die "this script targets macOS"
[ "$(uname -m)" = "arm64" ] || die "this script targets Apple Silicon (arm64), found $(uname -m)"
for tool in git cmake ninja clang++; do
  command -v "$tool" >/dev/null 2>&1 || die "missing prerequisite: $tool"
done
log "cmake: $(cmake --version | head -1)"
log "clang: $(/usr/bin/clang --version 2>/dev/null | head -1 || clang++ --version | head -1)"

# GameData: from the flag, else remembered, else the usual CrossOver location.
if [ -z "$GAMEDATA" ] && [ -f "$PROJ/fifastreet_manifest.toml" ]; then
  GAMEDATA="$(sed -n 's/^game_root = "\(.*\)"$/\1/p' "$PROJ/fifastreet_manifest.toml")"
  [ -n "$GAMEDATA" ] && log "reusing GameData from workspace: $GAMEDATA"
fi
if [ -z "$GAMEDATA" ] && [ -d "$HOME/Library/Application Support/CrossOver/Bottles/EA App/drive_c/users/crossover/AppData/Local/Games/FIFA Street PC/GameData" ]; then
  GAMEDATA="$HOME/Library/Application Support/CrossOver/Bottles/EA App/drive_c/users/crossover/AppData/Local/Games/FIFA Street PC/GameData"
  log "using CrossOver GameData: $GAMEDATA"
fi
[ -n "$GAMEDATA" ] || die "no GameData: pass --gamedata <path> (folder with default.xex, fifadllzf.xex.dll and the FootballCompEng DLC module)"
[ -f "$GAMEDATA/default.xex" ] || die "default.xex not found in $GAMEDATA"
[ -f "$GAMEDATA/fifadllzf.xex.dll" ] || die "fifadllzf.xex.dll not found in $GAMEDATA"
[ -f "$GAMEDATA/dlc/dlc_FootballCompEng/dlc/FootballCompEng/FootballCompEngzf.xex.dll" ] || die "FootballCompEng DLC module not found in $GAMEDATA"

# --- Stage 1: prepare the ReXGlue SDK ---------------------------------------
if [ ! -d "$SDK/.git" ]; then
  log "cloning rexglue-sdk into ReXGlue/ (10-20 min with submodules)"
  git clone https://github.com/rexglue/rexglue-sdk.git "$SDK" >>"$LOG" 2>&1 || die "clone failed"
fi
git -C "$SDK" checkout -q "$SDK_REV" 2>>"$LOG" || die "checkout of pinned revision $SDK_REV failed"
if ! git -C "$SDK" submodule status --recursive | grep -qv '^ '; then
  log "initializing submodules (10-20 min)"
  git -C "$SDK" submodule update --init --recursive >>"$LOG" 2>&1 || die "submodules failed"
fi

apply_patch() { # apply_patch <file> <label>
  local patch="$1" label="$2"
  if git -C "$SDK" apply --check "$patch" 2>>"$LOG"; then
    git -C "$SDK" apply "$patch" >>"$LOG" 2>&1 && log "$label applied" || die "$label failed to apply"
  elif git -C "$SDK" apply --check -R "$patch" 2>>"$LOG"; then
    log "$label already applied"
  else
    die "$label does not apply (ReXGlue not at the pinned revision, or dirty tree?)"
  fi
}
apply_patch "$REPO/patches/rexglue-local-changes.patch" "project patch"
apply_patch "$REPO/patches/rexglue-macos-addendum.patch" "macOS addendum"

# --- Stage 2: build the SDK --------------------------------------------------
# The game project lives inside this git repository, whose v1.x release tags
# clash with the SDK's version floor during configure; the ceiling makes git
# ignore the enclosing repository so the SDK keeps its dev version.
export GIT_CEILING_DIRECTORIES="$WORK"

log "=== Stage 2: SDK build (Vulkan backend, parallel $JOBS) ==="
cmake -S "$SDK" --preset mac-arm64 \
  -DREXGLUE_USE_VULKAN=ON -DREXGLUE_USE_D3D12=OFF \
  -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 >>"$LOG" 2>&1 \
  || die "SDK configure failed (see $LOG)"
cmake --build "$SDK/out/build/mac-arm64" --config Release --parallel "$JOBS" >>"$LOG" 2>&1 \
  || die "SDK build failed (see $LOG)"
REXGLUE="$SDK/out/mac-arm64/Release/rexglue"
[ -x "$REXGLUE" ] || die "rexglue tool not found at $REXGLUE"
log "SDK OK: $REXGLUE"

# --- Stage 3: codegen --------------------------------------------------------
if [ -f "$PROJ/generated/default/sources.cmake" ] \
   && [ -f "$PROJ/generated/fifadllzf_xex/sources.cmake" ] \
   && [ -f "$PROJ/generated/FootballCompEngzf_xex/sources.cmake" ]; then
  log "=== Stage 3: codegen already generated - skipping ==="
else
  log "=== Stage 3: codegen (analysis + C++ generation) ==="
  mkdir -p "$PROJ"
  cp -R "$REPO/Installer/recomp-template/." "$PROJ/"
  rm -f "$PROJ/fifastreet_manifest.toml"
  cat > "$PROJ/fifastreet_manifest.toml" <<EOF
[project]
name = "fifastreet"
sdk_version = "0.10.0"
game_root = "$GAMEDATA"

[entrypoint]
file_path = "$GAMEDATA/default.xex"
out_directory_path = "generated/default"
includes = []

[[modules]]
guest_path = "game:\\\\fifadllzf.xex.dll"
file_path = "$GAMEDATA/fifadllzf.xex.dll"
out_directory_path = "generated/fifadllzf_xex"
includes = ["config/fifadllzf_overrides.toml"]

[[modules]]
guest_path = "game:\\\\FootballCompEngzf.xex.dll"
file_path = "$GAMEDATA/dlc/dlc_FootballCompEng/dlc/FootballCompEng/FootballCompEngzf.xex.dll"
out_directory_path = "generated/FootballCompEngzf_xex"
includes = ["config/footballcompeng_overrides.toml"]
EOF
  ( cd "$PROJ" && "$REXGLUE" codegen "$PROJ/fifastreet_manifest.toml" ) >>"$LOG" 2>&1 \
    || die "codegen failed (see $LOG)"
  log "codegen OK (863 expected generated files)"
fi

# --- Stage 4: game build ------------------------------------------------------
log "=== Stage 4: game build (parallel $JOBS) ==="
cmake -S "$PROJ" --preset mac-arm64-release \
  -DREXSDK_DIR="$SDK" \
  -DREXGLUE_USE_VULKAN=ON -DREXGLUE_USE_D3D12=OFF \
  -DREXGLUE_OUTPUT_DIRECTORY="$PROJ/out/build/mac-arm64-release/runtime" \
  -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 >>"$LOG" 2>&1 \
  || die "game configure failed (see $LOG)"
cmake --build "$PROJ/out/build/mac-arm64-release" --parallel "$JOBS" >>"$LOG" 2>&1 \
  || die "game build failed (see $LOG)"

BUILD="$PROJ/out/build/mac-arm64-release"
[ -x "$BUILD/fifastreet" ] || die "fifastreet binary missing after build"
log "=== GAME BUILD COMPLETE (OK) ==="
log "--- outputs ---"
ls -la "$BUILD" | tee -a "$LOG"

# --- Stage 5: optional smoke test ---------------------------------------------
if [ "$SMOKE" -eq 1 ]; then
  log "=== Stage 5: smoke test (~45 s window) ==="
  [ -f "$BUILD/fifastreet.toml" ] || cp "$REPO/Installer/payload/Game/fifastreet.toml" "$BUILD/fifastreet.toml"
  [ -e "$BUILD/GameData" ] || ln -s "$GAMEDATA" "$BUILD/GameData"
  ( cd "$BUILD" && ./fifastreet ) >>"$LOG" 2>&1 &
  PID=$!
  sleep 25
  if kill -0 $PID 2>/dev/null; then
    log "still alive after 25 s; capturing screenshot"
    screencapture -x "$LOGDIR/first-launch.png" 2>>"$LOG" || log "screencapture failed (permissions?)"
    sleep 20
  fi
  if kill -0 $PID 2>/dev/null; then
    kill $PID 2>/dev/null; sleep 2; kill -9 $PID 2>/dev/null
    wait $PID 2>/dev/null
    log "smoke test OK: game ran for ~45 s, then terminated"
  else
    wait $PID; rc=$?
    log "smoke test: process exited early rc=$rc (check $LOG for the game log)"
  fi
fi

log "=== done ==="
