#!/usr/bin/env sh
set -eu

root="."
report_dir=".sdlc/doctor"
fail_on_warnings="false"

usage() {
  echo "Usage: sh tools/ai-sdlc/scripts/doctor-ai-sdlc.sh [--root PATH] [--report-directory PATH] [--fail-on-warnings]"
  echo "Requires PowerShell Core (pwsh) on macOS/Linux."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --report-directory) report_dir="$2"; shift 2 ;;
    --fail-on-warnings) fail_on_warnings="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell Core (pwsh) is required to run AI SDLC doctor on macOS/Linux." >&2
  exit 1
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
ps_script="$script_dir/doctor-ai-sdlc.ps1"

args="-NoProfile -ExecutionPolicy Bypass -File \"$ps_script\" -Root \"$root\" -ReportDirectory \"$report_dir\" -Pretty"
if [ "$fail_on_warnings" = "true" ]; then
  args="$args -FailOnWarnings"
fi

# shellcheck disable=SC2086
eval "pwsh $args"
