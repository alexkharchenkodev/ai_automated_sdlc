#!/usr/bin/env sh
set -eu

root="."
live_dir=".sdlc/live"
no_open="false"

usage() {
  echo "Usage: sh tools/ai-sdlc/scripts/start-ai-sdlc-dashboard.sh [--root PATH] [--live-directory PATH] [--no-open]"
  echo "Requires PowerShell Core (pwsh) on macOS/Linux."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --live-directory) live_dir="$2"; shift 2 ;;
    --no-open) no_open="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell Core (pwsh) is required to start the portable AI SDLC dashboard on macOS/Linux." >&2
  exit 1
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
ps_script="$script_dir/start-ai-sdlc-dashboard.ps1"
args="-NoProfile -ExecutionPolicy Bypass -File \"$ps_script\" -Root \"$root\" -LiveDirectory \"$live_dir\" -Pretty"

if [ "$no_open" = "true" ]; then
  args="$args -NoOpen"
fi

# shellcheck disable=SC2086
eval "pwsh $args"
