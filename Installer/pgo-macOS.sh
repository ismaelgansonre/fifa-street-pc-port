#!/bin/bash
# ReStreet -> macOS port - PGO pipeline (Profile-Guided Optimization, Apple clang)
#
# 3 phases for the mac-arm64-release game build:
#   1) ./Installer/pgo-macOS.sh instrument   # rebuild with -fprofile-instr-generate
#   2) run the game (see usage below), then
#      ./Installer/pgo-macOS.sh merge        # xcrun llvm-profdata merge -> .profdata
#   3) ./Installer/pgo-macOS.sh final        # rebuild with -fprofile-instr-use=<profdata>
#      ./Installer/pgo-macOS.sh revert       # back to the plain release build
#
# Conventions inherited from 04-game-build.sh: same build lock, logs under
# dist/mac-build/logs/, gamedata-free (builds the existing workspace in
# place), and NEVER wipes out/build (ninja keeps incremental state).
set -uo pipefail

REPO="/Users/ismael/Documents/GIT/fifa-street-pc-port"
WS="/Users/ismael/.openclaw-autoclaw/agents/auto-coder/workspace/.openclaw/tmp/fifa-port"
PROJ="$REPO/dist/mac-build/FifaStreetRex"
BUILD="$PROJ/out/build/mac-arm64-release"
LOGDIR="$REPO/dist/mac-build/logs"
LOG="$LOGDIR/pgo-build.log"
LOCK="$WS/.gamebuild.lock"   # same lock as 04-game-build.sh => mutual exclusion

# Profraw pattern: %m (merge pool) is REQUIRED here, not %p. The instrumented
# process is multi-module (host exe + libfifastreet_{fifadllzf,FootballCompEngzf}_xex
# dylibs + runtime); every module writes its own counters at exit, and with %p
# they would all resolve to the same filename and clobber each other. %m gives
# each module its own pooled file. %p is only safe for single-binary programs.
PROFRAW_DIR="${REX_PGO_PROFRAW_DIR:-/tmp}"
PROFDATA="${REX_PGO_PROFDATA:-$REPO/dist/mac-build/pgo/fifastreet.profdata}"

# Parallelism: 8 logical cores (6P+2E); compiles peak ~400 MB RSS per job, so
# 8 jobs fit in 16 GB (only the serial relink is memory-heavy).
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 6)
[ "$JOBS" -gt 8 ] && JOBS=8

# Never cache PGO stages: with a fixed profdata path ccache can return stale
# objects when the profile content changes (ccache issue #582). The launcher
# may persist in the build dir's CMakeCache from 04-game-build.sh, so disable
# ccache outright here. Remove this line only if you also remove the launcher
# exports from 04-game-build.sh.
export CCACHE_DISABLE=1

mkdir -p "$LOGDIR" "$REPO/dist/mac-build/pgo"
touch "$LOG"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

usage() {
  sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
  cat <<EOF

Typical full run (~15 min per rebuild on M1 Pro, -j8):
  1) ./Installer/pgo-macOS.sh instrument
  2) cd "$BUILD"
     LLVM_PROFILE_FILE=/tmp/fifastreet-%m.profraw ./fifastreet
     # play ~5-10 min of representative gameplay (menus -> a match -> skills)
     # quit the game NORMALLY (profraw is written at exit)
  3) ./Installer/pgo-macOS.sh merge
     ./Installer/pgo-macOS.sh final
Revert to the plain release build at any time:
  ./Installer/pgo-macOS.sh revert      # (or just re-run 04-game-build.sh)

Env overrides:
  REX_PGO_PROFDATA=/path/to/fifastreet.profdata
  REX_PGO_PROFRAW_DIR=/path/to/dir     # dir holding fifastreet-*.profraw
EOF
}

take_lock() {
  if ! mkdir "$LOCK" 2>/dev/null; then
    oldpid="$(cat "$LOCK/pid" 2>/dev/null || true)"
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
      log "game build already running (pid $oldpid) - exiting"
      exit 0
    fi
    rm -rf "$LOCK"; mkdir "$LOCK" 2>/dev/null || { log "lock failed"; exit 1; }
  fi
  echo $$ > "$LOCK/pid"
  trap 'rm -rf "$LOCK"' EXIT
}

check_prereqs() {
  [ -f "$PROJ/generated/default/sources.cmake" ] || { log "FATAL: codegen outputs missing (run 03 first)"; exit 2; }
  command -v xcrun >/dev/null || { log "FATAL: xcrun not available"; exit 2; }
}

# configure + build with the current REX_PGO_FLAGS exported by the caller
do_configure_build() {
  local stage="$1" rc
  cd "$PROJ" || { log "FATAL: project dir missing: $PROJ"; exit 3; }

  # Same as 04-game-build.sh: the enclosing repo's v1.x tags clash with the
  # SDK version floor; the ceiling makes git ignore the enclosing repo.
  export GIT_CEILING_DIRECTORIES="$REPO/dist/mac-build"

  log "=== $stage: cmake configure (mac-arm64-release, REX_PGO_FLAGS='${REX_PGO_FLAGS:-}') ==="
  cmake --preset mac-arm64-release \
    -DREXSDK_DIR="$REPO/ReXGlue" \
    -DREXGLUE_USE_VULKAN=ON -DREXGLUE_USE_D3D12=OFF \
    -DREXGLUE_OUTPUT_DIRECTORY="$BUILD/runtime" \
    -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.3 >>"$LOG" 2>&1
  rc=$?
  log "configure exit=$rc"
  [ $rc -ne 0 ] && { log "CONFIGURE FAILED"; exit 20; }

  log "=== $stage: build (Release, parallel $JOBS) ==="
  cmake --build --preset mac-arm64-release --parallel "$JOBS" >>"$LOG" 2>&1
  rc=$?
  log "build exit=$rc"
  [ $rc -ne 0 ] && { log "BUILD FAILED"; exit 21; }
}

# best-effort staleness report for the final build
report_profile_warnings() {
  local n
  n=$(grep -icE "profile data may be out of date|not (present|found) in profile|unprofiled" "$LOG" 2>/dev/null || true)
  if [ "${n:-0}" -gt 0 ]; then
    log "NOTE: $n profile-mismatch warning(s) in this build (code changed since profiling?). See log."
  else
    log "no profile-mismatch warnings"
  fi
}

cmd_instrument() {
  log "=== PGO PHASE 1: instrumented build ==="
  rm -f "$PROFRAW_DIR"/fifastreet-*.profraw
  log "cleared old profraw files in $PROFRAW_DIR"
  export REX_PGO_FLAGS="instrument"
  do_configure_build "instrument"
  local bin hits=0
  for bin in "$BUILD/fifastreet" \
             "$BUILD/libfifastreet_fifadllzf_xex.dylib" \
             "$BUILD/libfifastreet_FootballCompEngzf_xex.dylib"; do
    if [ -f "$bin" ] && otool -l "$bin" 2>/dev/null | grep -q __llvm_prf; then
      log "instrumented OK: $bin"
      hits=$((hits+1))
    else
      log "WARNING: no profile counters found in $bin"
    fi
  done
  [ "$hits" -eq 0 ] && { log "FATAL: nothing was instrumented"; exit 22; }
  log "=== PHASE 1 DONE === Next: run the game with"
  log "  LLVM_PROFILE_FILE=/tmp/fifastreet-%m.profraw ./fifastreet"
  log "play representative gameplay, then quit NORMALLY, then: $0 merge"
}

cmd_merge() {
  log "=== PGO PHASE 2: merge profiles ==="
  local -a raws=()
  local f
  for f in "$PROFRAW_DIR"/fifastreet-*.profraw; do
    [ -f "$f" ] || continue
    [ -s "$f" ] || { log "skipping empty $f"; continue; }
    raws+=("$f")
  done
  [ ${#raws[@]} -eq 0 ] && { log "FATAL: no $PROFRAW_DIR/fifastreet-*.profraw found (run the instrumented game first)"; exit 23; }
  for f in "${raws[@]}"; do
    log "input: $f ($(du -h "$f" | cut -f1))"
  done
  local tmp_out="$PROFDATA.merging"
  xcrun llvm-profdata merge -sparse -output="$tmp_out" "${raws[@]}" >>"$LOG" 2>&1 \
    || { log "FATAL: llvm-profdata merge failed (see log)"; rm -f "$tmp_out"; exit 24; }
  mv -f "$tmp_out" "$PROFDATA"
  log "merged -> $PROFDATA ($(du -h "$PROFDATA" | cut -f1), ${#raws[@]} input(s))"
  log "top functions in profile:"
  xcrun llvm-profdata show --counts --topn=5 "$PROFDATA" 2>>"$LOG" | tail -n +1 | tee -a "$LOG" | head -20 || true
  log "=== PHASE 2 DONE === Next: $0 final"
}

cmd_final() {
  [ -s "$PROFDATA" ] || { log "FATAL: $PROFDATA missing/empty - run '$0 merge' first"; exit 25; }
  log "=== PGO PHASE 3: optimized build using $PROFDATA ==="
  export REX_PGO_FLAGS="use:$PROFDATA"
  do_configure_build "final"
  [ -f "$BUILD/fifastreet" ] || { log "FATAL: $BUILD/fifastreet missing after build"; exit 22; }
  log "built: $BUILD/fifastreet ($(date -r "$BUILD/fifastreet" '+%F %T'))"
  log "guest dylibs: $(ls -1 "$BUILD"/libfifastreet_*.dylib 2>/dev/null | tr '\n' ' ')"
  # sanity: final build must NOT carry instrumentation counters
  if otool -l "$BUILD/fifastreet" 2>/dev/null | grep -q __llvm_prf; then
    log "WARNING: fifastreet still contains profile counters (stale instrumented link?)"
  else
    log "clean: no instrumentation counters in final binary"
  fi
  report_profile_warnings
  log "=== PHASE 3 DONE (PGO build ready) ==="
}

cmd_revert() {
  log "=== PGO REVERT: plain release build (no REX_PGO_FLAGS) ==="
  unset REX_PGO_FLAGS
  do_configure_build "revert"
  log "=== REVERT DONE (equivalent to re-running 04-game-build.sh) ==="
}

case "${1:-help}" in
  instrument) take_lock; check_prereqs; cmd_instrument ;;
  merge)      check_prereqs; cmd_merge ;;
  final)      take_lock; check_prereqs; cmd_final ;;
  revert)     take_lock; check_prereqs; cmd_revert ;;
  help|-h|--help) usage ;;
  *) echo "unknown command: $1"; echo; usage; exit 1 ;;
esac
