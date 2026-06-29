#!/usr/bin/env sh
set -eu

target="."
manifest=""
include_generated="false"
force_fallback="false"
dry_run="false"

usage() {
  echo "Usage: sh uninstall-ai-sdlc.sh [--target PATH] [--manifest PATH] [--include-generated] [--force-fallback] [--dry-run]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --manifest) manifest="$2"; shift 2 ;;
    --include-generated) include_generated="true"; shift ;;
    --force-fallback) force_fallback="true"; shift ;;
    --dry-run) dry_run="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

target_dir=$(CDPATH= cd "$target" && pwd -P)
[ -n "$manifest" ] || manifest="$target_dir/.sdlc/ai-sdlc-install-manifest.json"

tmp_files="${TMPDIR:-/tmp}/ai-sdlc-uninstall-files-$$.txt"
: > "$tmp_files"

extract_manifest_files() {
  awk '
    /"managedFiles"[[:space:]]*:/ { inside=1; next }
    inside && /\]/ { inside=0; next }
    inside {
      gsub(/^[[:space:]]*"/, "")
      gsub(/",?[[:space:]]*$/, "")
      if (length($0) > 0) print $0
    }
  ' "$manifest"
}

fallback_files() {
  for dir in docs/SDLC docs/LLM tools/ai-sdlc dashboard; do
    if [ -d "$target_dir/$dir" ]; then
      (cd "$target_dir" && find "$dir" -type f)
    fi
  done
  for file in .github/PULL_REQUEST_TEMPLATE.md .github/workflows/ai-sdlc.yml AGENTS.md; do
    [ -f "$target_dir/$file" ] && printf "%s\n" "$file"
  done
}

used_fallback="false"
if [ -f "$manifest" ]; then
  extract_manifest_files > "$tmp_files"
elif [ "$force_fallback" = "true" ]; then
  fallback_files | sort -u > "$tmp_files"
  used_fallback="true"
else
  cat <<EOF
{
  "targetRoot": "$target_dir",
  "passed": false,
  "dryRun": $dry_run,
  "message": "Install manifest not found. Re-run with --force-fallback to remove the standard AI SDLC paths.",
  "manifestPath": "$manifest"
}
EOF
  rm -f "$tmp_files"
  exit 2
fi

removed_count=0
missing_count=0
while IFS= read -r relative; do
  [ -n "$relative" ] || continue
  path="$target_dir/$relative"
  if [ -f "$path" ]; then
    if [ "$dry_run" != "true" ]; then
      rm -f "$path"
    fi
    removed_count=$((removed_count + 1))
  else
    missing_count=$((missing_count + 1))
  fi
done < "$tmp_files"

removed_generated=""
if [ "$include_generated" = "true" ]; then
  for dir in .sdlc/local-pipeline .sdlc/live .sdlc/approvals; do
    if [ -e "$target_dir/$dir" ]; then
      [ "$dry_run" = "true" ] || rm -rf "$target_dir/$dir"
      removed_generated="$removed_generated $dir"
    fi
  done
fi

if [ -f "$manifest" ]; then
  [ "$dry_run" = "true" ] || rm -f "$manifest"
  removed_count=$((removed_count + 1))
fi

if [ "$dry_run" != "true" ]; then
  for dir in dashboard tools/ai-sdlc/scripts tools/ai-sdlc/config tools/ai-sdlc tools docs/SDLC/templates docs/SDLC docs/LLM .github/workflows .github .sdlc; do
    rmdir "$target_dir/$dir" 2>/dev/null || true
  done
fi

rm -f "$tmp_files"

cat <<EOF
{
  "targetRoot": "$target_dir",
  "passed": true,
  "dryRun": $dry_run,
  "includeGenerated": $include_generated,
  "usedFallback": $used_fallback,
  "removedCount": $removed_count,
  "missingCount": $missing_count,
  "removedGeneratedDirectories": "$removed_generated"
}
EOF
