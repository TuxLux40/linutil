#!/usr/bin/env bash
set -euo pipefail

# Require a TTY so the TUI can start correctly
if [ ! -t 1 ]; then
  echo "dev-run-tui.sh must be run in a terminal (TTY required). Use the integrated terminal instead of Run Code." >&2
  exit 1
fi

# Always run from repo root so cargo finds the workspace
cd "$(dirname "$0")"

PROFILE_FLAG=()
BIN_PATH="target/debug/linutil"

if [[ "${1:-}" == "--release" ]]; then
  PROFILE_FLAG=(--release)
  BIN_PATH="target/release/linutil"
  shift
fi

cargo build -p linutil_tui "${PROFILE_FLAG[@]}"
"${BIN_PATH}" "$@"
