#!/usr/bin/env sh
set -eu

root="."
changed_files=""
changed_files_path=""
task=""
report_dir=".sdlc/local-pipeline"
live_dir=".sdlc/live"
batch_id=""
task_id=""
task_order=""
skip_validation="false"
open_dashboard="false"

usage() {
  echo "Usage: sh tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.sh [--root PATH] [--changed-file PATH] [--changed-files-path PATH] [--task TEXT] [--batch-id ID] [--task-id ID] [--task-order N] [--report-directory PATH] [--live-directory PATH] [--skip-validation] [--open-dashboard]"
  echo "Requires PowerShell Core (pwsh) on macOS/Linux."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --changed-file) changed_files="$changed_files
$2"; shift 2 ;;
    --changed-files-path) changed_files_path="$2"; shift 2 ;;
    --task) task="$2"; shift 2 ;;
    --report-directory) report_dir="$2"; shift 2 ;;
    --live-directory) live_dir="$2"; shift 2 ;;
    --batch-id) batch_id="$2"; shift 2 ;;
    --task-id) task_id="$2"; shift 2 ;;
    --task-order) task_order="$2"; shift 2 ;;
    --skip-validation) skip_validation="true"; shift ;;
    --open-dashboard) open_dashboard="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell Core (pwsh) is required to run the portable AI SDLC orchestrator on macOS/Linux." >&2
  exit 1
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
ps_script="$script_dir/run-ai-sdlc-orchestrator.ps1"

tmp_changed=""
if [ -n "$changed_files" ]; then
  tmp_changed="${TMPDIR:-/tmp}/ai-sdlc-orchestrator-changed-files-$$.txt"
  printf "%s\n" "$changed_files" | sed '/^[[:space:]]*$/d' > "$tmp_changed"
  changed_files_path="$tmp_changed"
fi

args="-NoProfile -ExecutionPolicy Bypass -File \"$ps_script\" -Root \"$root\" -ReportDirectory \"$report_dir\" -LiveDirectory \"$live_dir\" -Pretty"

if [ -n "$changed_files_path" ]; then
  args="$args -ChangedFilesPath \"$changed_files_path\""
fi
if [ -n "$task" ]; then
  args="$args -Task \"$task\""
fi
if [ -n "$batch_id" ]; then
  args="$args -BatchId \"$batch_id\""
fi
if [ -n "$task_id" ]; then
  args="$args -TaskId \"$task_id\""
fi
if [ -n "$task_order" ]; then
  args="$args -TaskOrder $task_order"
fi
if [ "$skip_validation" = "true" ]; then
  args="$args -SkipValidationExecution"
fi
if [ "$open_dashboard" = "true" ]; then
  args="$args -OpenDashboard"
fi

# shellcheck disable=SC2086
eval "pwsh $args"

if [ -n "$tmp_changed" ]; then
  rm -f "$tmp_changed"
fi
