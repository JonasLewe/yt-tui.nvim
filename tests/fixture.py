"""Small real process used to exercise the Neovim terminal lifecycle."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tty

mode, capture = sys.argv[1:3]
Path(capture).write_text(json.dumps(sys.argv[3:]), encoding="utf-8")
Path(capture + ".pid").write_text(str(os.getpid()), encoding="utf-8")
Path(capture + ".host-env").write_text(os.environ.get("YT_TUI_NVIM_HIDE", ""), encoding="utf-8")
print("YT_FIXTURE_READY", flush=True)

if mode in {"raw", "quit-controls"}:
    tty.setraw(sys.stdin.fileno())
    Path(capture + ".raw-ready").touch()
    editing = False
    with Path(capture + ".input").open("wb", buffering=0) as received:
        while data := os.read(sys.stdin.fileno(), 1024):
            received.write(data)
            if mode == "quit-controls":
                for key in data:
                    if editing:
                        if key == 27:
                            editing = False
                        continue
                    if key == ord("e"):
                        editing = True
                    elif key == ord("Q"):
                        sys.exit(0)
                    elif key == ord("q"):
                        if os.environ.get("YT_TUI_NVIM_HIDE") == "1":
                            os.write(sys.stdout.fileno(), b"\x1b]777;yt-tui;hide\x07")
                        else:
                            sys.exit(0)
                    elif key == ord("b"):
                        os.write(sys.stdout.fileno(),
                                 b"\x1b]777;other;hide\x07"
                                 b"\x1b]777;yt-tui;hide-extra\x07"
                                 b"\x1b]777;yt-tui;hide;extra\x1b\\"
                                 b"PROBES_DONE")
    sys.exit(0)

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
