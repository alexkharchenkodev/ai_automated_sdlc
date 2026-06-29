#!/usr/bin/env sh
set -eu

root="."
report_dir=".sdlc/local-pipeline"
allow_review="false"

usage() {
  echo "Usage: sh tools/ai-sdlc/scripts/verify-sdlc-compliance.sh [--root PATH] [--report-directory PATH] [--allow-review-required]"
  echo "Requires PowerShell Core (pwsh) on macOS/Linux."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --report-directory) report_dir="$2"; shift 2 ;;
    --allow-review-required) allow_review="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell Core (pwsh) is required to verify AI SDLC compliance on macOS/Linux." >&2
  exit 1
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
ps_script="$script_dir/verify-sdlc-compliance.ps1"

args="-NoProfile -ExecutionPolicy Bypass -File \"$ps_script\" -Root \"$root\" -ReportDirectory \"$report_dir\" -Pretty"
if [ "$allow_review" = "true" ]; then
  args="$args -AllowReviewRequired"
fi

# shellcheck disable=SC2086
eval "pwsh $args"
