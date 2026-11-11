#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v nvim >/dev/null
command -v python3 >/dev/null

NVIM_LOG_FILE="${TMPDIR:-/tmp}/yt-tui-nvim-tests.log" \
  YT_TUI_TEST_ROOT="$repo_root" nvim --headless -u NONE -i NONE \
  -c 'lua dofile(vim.env.YT_TUI_TEST_ROOT .. "/tests/run.lua")'
