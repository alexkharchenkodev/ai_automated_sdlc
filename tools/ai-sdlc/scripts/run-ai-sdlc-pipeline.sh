#!/usr/bin/env sh
set -eu

root="."
changed_files=""
task=""
report_dir=".sdlc/local-pipeline"
skip_validation="false"

usage() {
  echo "Usage: sh tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.sh [--root PATH] [--changed-file PATH] [--changed-files-path PATH] [--task TEXT] [--report-directory PATH] [--skip-validation]"
  echo "Requires PowerShell Core (pwsh) on macOS/Linux."
}

changed_file_args=""
changed_files_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --root)
      root="$2"
      shift 2
      ;;
    --changed-file)
      changed_files="$changed_files
$2"
      shift 2
      ;;
    --changed-files-path)
      changed_files_path="$2"
      shift 2
      ;;
    --task)
      task="$2"
      shift 2
      ;;
    --report-directory)
      report_dir="$2"
      shift 2
      ;;
    --skip-validation)
      skip_validation="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v pwsh >/dev/null 2>&1; then
  echo "PowerShell Core (pwsh) is required to run the portable AI SDLC pipeline on macOS/Linux." >&2
  exit 1
fi

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
ps_script="$script_dir/run-ai-sdlc-pipeline.ps1"

tmp_changed=""
if [ -n "$changed_files" ]; then
  tmp_changed="${TMPDIR:-/tmp}/ai-sdlc-changed-files-$$.txt"
  printf "%s\n" "$changed_files" | sed '/^[[:space:]]*$/d' > "$tmp_changed"
  changed_files_path="$tmp_changed"
fi

args="-NoProfile -ExecutionPolicy Bypass -File \"$ps_script\" -Root \"$root\" -ReportDirectory \"$report_dir\" -Pretty"

if [ -n "$changed_files_path" ]; then
  args="$args -ChangedFilesPath \"$changed_files_path\""
fi

if [ -n "$task" ]; then
  args="$args -Task \"$task\""
fi

if [ "$skip_validation" = "true" ]; then
  args="$args -SkipValidationExecution"
fi

# shellcheck disable=SC2086
eval "pwsh $args"

if [ -n "$tmp_changed" ]; then
  rm -f "$tmp_changed"
fi
