#!/bin/zsh
# Launch the preserved baseline; count one noisy warning without hiding other logs.
set -e
REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec python3 "$REPO/scripts/run-logged.py" --capture-runtime --log-dir "$REPO/dist/logs/play" -- \
    zsh "$REPO/dist/checkpoints/2026-10-14-codegen-validated/launch.sh" "$@"
