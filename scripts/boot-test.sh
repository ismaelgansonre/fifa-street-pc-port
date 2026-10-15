#!/bin/zsh
# Test de boot fenêtré + capture d'écran (J3).
# Usage : zsh scripts/boot-test.sh [secondes]   (défaut 30)
# Sorties : dist/logs/boot-console.log, dist/logs/boot-title.png, build/logs/*
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WAIT=${1:-75}
LOGDIR="$REPO/dist/logs"
mkdir -p "$LOGDIR"
cd "$REPO/build" || exit 1

rm -f "$REPO/build/logs"/fifastreet_00*.log

DYLD_LIBRARY_PATH="$PWD" ./fifastreet \
    --no-fullscreen \
    --resolution 1280x720 \
    --game_data_root "$REPO/dist/GameData" \
    --writable_code_segments \
    --log_level debug \
    > "$LOGDIR/boot-console.log" 2>&1 &
GPID=$!
echo "game PID=$GPID (attente ${WAIT}s)"

sleep "$WAIT"
ALIVE=no
kill -0 $GPID 2>/dev/null && ALIVE=yes

WID=$(swift "$REPO/scripts/winid.swift" 2>/dev/null)
SHOT=no
if [ -n "$WID" ]; then
    screencapture -x -l "$WID" "$LOGDIR/boot-title.png" 2>/dev/null && SHOT=yes
fi

kill $GPID 2>/dev/null
sleep 1
pkill -f "build/fifastreet" 2>/dev/null

echo "ALIVE=$ALIVE WID=${WID:-none} SCREENSHOT=$SHOT -> $LOGDIR/boot-title.png"
echo "--- dernières lignes runtime ---"
tail -8 "$REPO/build/logs"/fifastreet_00*.log 2>/dev/null
