"""Create an isolated runtime variant with only a replacement GPU plugin."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("label")
parser.add_argument("--menu-trace", action="store_true",
                    help="Enable menu frame diagnostics in the replacement GPU plugin")
args = parser.parse_args()
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", args.label):
    parser.error("label must contain only letters, numbers, dots, dashes or underscores")
baseline = root / "dist/checkpoints/2026-10-14-codegen-validated"
plugin = root / "sdk-src/out/mac-arm64/Release/librexgpu-xenos.dylib"
destination = root / "dist/render-tests" / args.label
if destination.exists():
    raise SystemExit(f"Already exists: {destination}")
if not plugin.is_file() or not (baseline / "runtime/fifastreet").is_file():
    raise SystemExit("Missing baseline or rebuilt GPU plugin")
pending = destination.with_name(destination.name + ".incomplete")
pending.mkdir(parents=True, exist_ok=False)
runtime = pending / "runtime"
runtime.mkdir()
for source in (baseline / "runtime").iterdir():
    if source.name == "logs":
        continue
    target = runtime / source.name
    result = subprocess.run(["cp", "-cRp", str(source), str(target)], capture_output=True)
    if result.returncode:
        if source.is_dir():
            shutil.copytree(source, target, dirs_exist_ok=True)
        else:
            shutil.copy2(source, target)
shutil.copy2(plugin, runtime / plugin.name)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


baseline_metadata = json.loads((baseline / "checkpoint.json").read_text())
for name, expected in baseline_metadata["runtime_sha256"].items():
    if name != "runtime/librexgpu-xenos.dylib":
        assert digest(pending / name) == expected, f"Unexpected change: {name}"
assert digest(runtime / plugin.name) != baseline_metadata["runtime_sha256"]["runtime/librexgpu-xenos.dylib"]
patch = root / "patches/rexglue-v0.10.0-vulkan-3d-textures.patch"
shutil.copy2(patch, pending / patch.name)
if args.menu_trace:
    patch = root / "patches/rexglue-v0.10.0-menu-frame-trace.patch"
    shutil.copy2(patch, pending / patch.name)
(pending / "variant.json").write_text(json.dumps({
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "baseline": str(baseline),
    "gpu_sha256": digest(runtime / plugin.name),
    "only_binary_changed": "librexgpu-xenos.dylib",
    "boot_status": "not_verified",
    "shader_cache": "isolated; created on first launch",
    "menu_trace": args.menu_trace,
}, indent=2) + "\n")
# Keep all data files external; cache and logs belong to this variant.
(pending / "launch.sh").write_text(
    '#!/bin/zsh\nset -e\n'
    'HERE="$(cd "$(dirname "$0")" && pwd)"\n'
    'cd "$HERE/runtime"\n'
    'export DYLD_LIBRARY_PATH="$PWD"\n'
    'exec python3 ' + "'" + str(root / "scripts/run-logged.py").replace("'", "'\\''") + "'"
    + ' --capture-runtime' + (' --capture-gpu-trace' if args.menu_trace else '')
    + ' --log-dir "$HERE/logs" -- ./fifastreet'
    + ' --no-fullscreen --resolution 1280x720 --writable_code_segments'
    + ' --cache_root="$HERE/cache" --game_data_root '
    + "'" + str(root / "dist/GameData").replace("'", "'\\''") + "'"
    + ' "$@"\n')
(pending / "launch.sh").chmod(0o755)
pending.rename(destination)
print(f"Prepared: {destination}")
print("Only GPU plugin changed; all other runtime files verified against baseline.")
print(f"Run: zsh {destination / 'launch.sh'}")
