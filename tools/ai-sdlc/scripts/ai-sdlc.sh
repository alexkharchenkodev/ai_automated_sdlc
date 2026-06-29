#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/ai-sdlc.ps1" "$@"

