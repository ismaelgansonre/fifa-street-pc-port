"""Preserve a compiled build and its inputs without changing the active build."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
label = sys.argv[1] if len(sys.argv) == 2 else ""
if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]*", label):
    raise SystemExit("Usage: python3 scripts/freeze-build.py <unique-label>")
destination = root / "dist/checkpoints" / label
if destination.exists():
    raise SystemExit(f"Checkpoint already exists: {destination}")
runtime = root / "build"
required = [runtime / "fifastreet", runtime / "fifastreet_fifadllzf_xex",
            runtime / "fifastreet_FootballCompEngzf_xex",
            runtime / "librexruntime.dylib", runtime / "librexgpu-xenos.dylib"]
for path in required:
    if not path.is_file():
        raise SystemExit(f"Missing compiled file: {path}")

# Keep interrupted captures distinguishable from completed checkpoints.
pending = destination.with_name(destination.name + ".incomplete")
pending.mkdir(parents=True, exist_ok=False)
(pending / "runtime").mkdir()
(pending / "project").mkdir()
(pending / "validation").mkdir()


def copy(source, target):
    """Use APFS copy-on-write clones; fall back to an ordinary copy."""
    if not source.exists():
        return
    flags = "-cRp" if source.is_dir() else "-cp"
    result = subprocess.run(["cp", flags, str(source), str(target)],
                            capture_output=True)
    if result.returncode:
        if source.is_dir():
            shutil.copytree(source, target, dirs_exist_ok=True)
        else:
            shutil.copy2(source, target)


for path in required + sorted(runtime.glob("*.dylib")):
    copy(path, pending / "runtime" / path.name)
for name in ("vulkan", "fifastreet.toml", "logs"):
    copy(runtime / name, pending / "runtime" / name)
for name in ("src", "config", "scripts", "patches", "CMakeLists.txt",
             "CMakePresets.json", "fifastreet_manifest.toml", "HANDOFF.md"):
    copy(root / name, pending / "project" / name)
copy(root / "generated", pending / "generated")
copy(root / "dist/sdk", pending / "sdk")
copy(runtime / "CMakeCache.txt", pending / "validation/CMakeCache.txt")

checks = {}
for name in ("verify_direct_branches.py", "verify_ctr_region.py",
             "verify_allocation_region.py"):
    result = subprocess.run([sys.executable, str(root / "scripts" / name)],
                            cwd=root, capture_output=True, text=True)
    (pending / "validation" / (name + ".log")).write_text(
        result.stdout + result.stderr)
    checks[name] = result.returncode


def git(*args):
    return subprocess.check_output(
        ["git", "-c", "core.fsmonitor=false", *args], cwd=root, text=True)


(pending / "validation/working-tree.diff").write_text(git("diff", "HEAD", "--binary"))
hashes = {}
for path in sorted((pending / "runtime").rglob("*")):
    if path.is_file() and "logs" not in path.relative_to(pending / "runtime").parts:
        with path.open("rb") as stream:
            hashes[str(path.relative_to(pending))] = hashlib.file_digest(stream, "sha256").hexdigest()
metadata = {
    "label": label,
    "created_utc": datetime.now(timezone.utc).isoformat(),
    "git_commit": git("rev-parse", "HEAD").strip(),
    "git_branch": git("branch", "--show-current").strip(),
    "working_tree": git("status", "--short"),
    "control_flow_checks": checks,
    "boot_status": "not_verified",
    "game_data": str(root / "dist/GameData"),
    "runtime_sha256": hashes,
}
(pending / "checkpoint.json").write_text(json.dumps(metadata, indent=2) + "\n")
# The launcher uses the preserved runtime, with external game data kept in place.
(pending / "launch.sh").write_text(
    '#!/bin/zsh\nset -e\n'
    'HERE="$(cd "$(dirname "$0")" && pwd)"\n'
    'cd "$HERE/runtime"\n'
    'export DYLD_LIBRARY_PATH="$PWD"\n'
    'exec ./fifastreet --no-fullscreen --resolution 1280x720 '
    '--writable_code_segments --game_data_root '
    + "'" + str(root / "dist/GameData").replace("'", "'\\''") + "'"
    + ' "$@"\n')
(pending / "launch.sh").chmod(0o755)
pending.rename(destination)
print(f"Preserved: {destination}")
print("Control flow: " + ("PASS" if all(code == 0 for code in checks.values()) else "FAIL (see validation/)"))
print("Boot: not verified")
print(f"Run without rebuilding: zsh {destination / 'launch.sh'}")
