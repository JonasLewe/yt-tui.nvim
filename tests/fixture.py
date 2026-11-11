"""Small real process used to exercise the Neovim terminal lifecycle."""

import json
from pathlib import Path
import sys

mode, capture = sys.argv[1:3]
Path(capture).write_text(json.dumps(sys.argv[3:]), encoding="utf-8")
print("YT_FIXTURE_READY", flush=True)

if mode == "success":
    sys.exit(0)
if mode == "failure":
    print("YT_FIXTURE_FAILED", flush=True)
    sys.exit(7)

for line in sys.stdin:
    if line.strip() == "exit":
        break
    print("YT_FIXTURE_INPUT: " + line.rstrip(), flush=True)
