"""Run a command with a complete raw log and a counted primitive-restart warning."""
import argparse
from datetime import datetime
from pathlib import Path
import signal
import subprocess
import sys
import threading
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--log-dir", type=Path, required=True)
parser.add_argument("--capture-runtime", action="store_true",
                    help="Capture ReXGlue's separate runtime log in this run and display it live")
parser.add_argument("--capture-gpu-trace", action="store_true",
                    help="Enable the diagnostic GPU plugin's per-frame CSV trace")
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command
if command[:1] == ["--"]:
    command = command[1:]
if not command:
    parser.error("provide a command after --")
run = args.log_dir.resolve() / datetime.now().strftime("%Y%m%d-%H%M%S-%f")
run.mkdir(parents=True, exist_ok=False)
message = b"Metal does not support disabling primitive restart."
count = 0
last_report = time.monotonic()
process = None
lock = threading.RLock()
finished = threading.Event()
runtime_thread = None
if args.capture_runtime:
    command += [f"--log_file={run / 'runtime.log'}", "--log_flush_interval=1"]
if args.capture_gpu_trace:
    command += [f"--vulkan_menu_trace={run / 'gpu-frames.csv'}"]

with (run / "console.raw.log").open("wb") as raw, \
        (run / "console.filtered.log").open("wb") as filtered, \
        (run / "primitive-restart.log").open("wb") as repeated:

    def show(line):
        with lock:
            filtered.write(line)
            filtered.flush()
            sys.stdout.buffer.write(line)
            sys.stdout.buffer.flush()

    def display(line):
        global count, last_report
        with lock:
            if message in line and (b"mvk-warn" in line or b"Vulkan Warning" in line):
                count += 1
                repeated.write(line)
                repeated.flush()
                if count == 1:
                    show(line)
                now = time.monotonic()
                if now - last_report >= 5:
                    show(f"[log-summary] primitive restart: {count} log occurrences (details in primitive-restart.log)\n".encode())
                    last_report = now
            else:
                show(line)

    def follow_runtime():
        runtime_path = run / "runtime.log"
        while not runtime_path.exists():
            if finished.wait(0.1):
                if not runtime_path.exists():
                    return
        stream = runtime_path.open("rb")
        try:
            while True:
                line = stream.readline()
                if line:
                    display(b"[runtime] " + line)
                else:
                    # ReXGlue rotates its log. Follow the new file after draining
                    # the old one, rather than silently losing later diagnostics.
                    import os
                    try:
                        rotated = runtime_path.stat().st_ino != os.fstat(stream.fileno()).st_ino
                    except FileNotFoundError:
                        rotated = False
                    if rotated:
                        stream.close()
                        stream = runtime_path.open("rb")
                        continue
                    if finished.is_set():
                        return
                    finished.wait(0.1)
        finally:
            stream.close()

    show(f"[logs] {run}\n".encode())
    try:
        # stdout and stderr stay in one ordered stream. Keep the raw bytes.
        process = subprocess.Popen(command, stdout=subprocess.PIPE,
                                   stderr=subprocess.STDOUT, start_new_session=True)
        if args.capture_runtime:
            runtime_thread = threading.Thread(target=follow_runtime, daemon=True)
            runtime_thread.start()
        for line in process.stdout:
            raw.write(line)
            raw.flush()
            display(line)
        returncode = process.wait()
    except KeyboardInterrupt:
        if process is not None and process.poll() is None:
            # The game has a separate process group so Ctrl-C reaches it explicitly.
            import os
            os.killpg(process.pid, signal.SIGINT)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait()
        returncode = 130
    finally:
        finished.set()
        if runtime_thread is not None:
            runtime_thread.join()
        locations = "console.raw.log and runtime.log" if args.capture_runtime else "console.raw.log"
        show(f"[log-summary] primitive restart total: {count}; full logs: {locations}\n".encode())
        (run / "summary.txt").write_text(f"primitive_restart_count={count}\n")

raise SystemExit(returncode if returncode >= 0 else 128 - returncode)
