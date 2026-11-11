"""Small real process used to exercise the Neovim terminal lifecycle."""

import json
import os
from pathlib import Path
import subprocess
import sys

mode, capture = sys.argv[1:3]
Path(capture).write_text(json.dumps(sys.argv[3:]), encoding="utf-8")
Path(capture + ".pid").write_text(str(os.getpid()), encoding="utf-8")
print("YT_FIXTURE_READY", flush=True)

child = None
if mode == "nested":
    child = subprocess.Popen(
        [sys.argv[3], "--headless", "-u", "NONE", "-i", "NONE", "-c", "sleep 30"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    Path(capture + ".child-pid").write_text(str(child.pid), encoding="utf-8")

if mode == "success":
    sys.exit(0)
if mode == "failure":
    print("YT_FIXTURE_FAILED", flush=True)
    sys.exit(7)

for line in sys.stdin:
    if line.strip() == "exit":
        break
    if line.strip() == "fail":
        print("YT_FIXTURE_FAILED", flush=True)
        sys.exit(7)
    print("YT_FIXTURE_INPUT: " + line.rstrip(), flush=True)

if child is not None:
    child.terminate()
    child.wait(timeout=3)
