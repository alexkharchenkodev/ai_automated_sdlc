#!/usr/bin/env sh
set -eu

target="."
source_root=""
force_configs="false"
include_agents="false"
include_github="false"
dry_run="false"

usage() {
  echo "Usage: sh update-ai-sdlc.sh [--target PATH] [--source PATH] [--force-configs] [--include-agents] [--include-github] [--dry-run]"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --source) source_root="$2"; shift 2 ;;
    --force-configs) force_configs="true"; shift ;;
    --include-agents) include_agents="true"; shift ;;
    --include-github) include_github="true"; shift ;;
    --dry-run) dry_run="true"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
[ -n "$source_root" ] || source_root="$script_dir"
source_dir=$(CDPATH= cd "$source_root" && pwd -P)
target_dir=$(CDPATH= cd "$target" && pwd -P)

for required in docs tools dashboard; do
  if [ ! -d "$source_dir/$required" ]; then
    echo "Source root does not look like an AI SDLC framework checkout. Missing: $required" >&2
    exit 1
  fi
done

is_protected() {
  case "$1" in
    AGENTS.md|\
    tools/ai-sdlc/config/project-profile.yaml|\
    tools/ai-sdlc/config/context_memory.yaml|\
    tools/ai-sdlc/config/integrations.yaml|\
    tools/ai-sdlc/config/token_budget.yaml|\
    tools/ai-sdlc/config/execution_lanes.yaml|\
    tools/ai-sdlc/config/mcp_servers.example.yaml)
      return 0
      ;;
    *) return 1 ;;
  esac
}

updated_count=0
staged_count=0
unchanged_count=0
manifest_files="${TMPDIR:-/tmp}/ai-sdlc-update-managed-$$.txt"
: > "$manifest_files"

copy_one() {
  src="$1"
  rel="$2"
  dest="$target_dir/$rel"
  [ "$dry_run" = "true" ] || mkdir -p "$(dirname "$dest")"
  printf "%s\n" "$rel" >> "$manifest_files"

  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    unchanged_count=$((unchanged_count + 1))
    return 0
  fi

  if [ -f "$dest" ] && is_protected "$rel" && [ "$force_configs" != "true" ]; then
    [ "$dry_run" = "true" ] || cp "$src" "$dest.new"
    printf "%s.new\n" "$rel" >> "$manifest_files"
    staged_count=$((staged_count + 1))
    return 0
  fi

  [ "$dry_run" = "true" ] || cp "$src" "$dest"
  updated_count=$((updated_count + 1))
}

copy_tree() {
  src_root="$1"
  dest_root="$2"
  [ -d "$src_root" ] || return 0
  tmp_list="${TMPDIR:-/tmp}/ai-sdlc-update-list-$$.txt"
  (cd "$src_root" && find . -type f) > "$tmp_list"
  while IFS= read -r relative; do
    clean=${relative#./}
    copy_one "$src_root/$relative" "$dest_root/$clean"
  done < "$tmp_list"
  rm -f "$tmp_list"
}

copy_tree "$source_dir/docs" "docs"
copy_tree "$source_dir/tools" "tools"
copy_tree "$source_dir/dashboard" "dashboard"
copy_tree "$source_dir/adapters" "adapters"
[ "$include_github" = "true" ] && copy_tree "$source_dir/github" ".github"
[ "$include_agents" = "true" ] && [ -f "$source_dir/AGENTS.md.template" ] && copy_one "$source_dir/AGENTS.md.template" "AGENTS.md"

manifest_dir="$target_dir/.sdlc"
manifest_path="$manifest_dir/ai-sdlc-install-manifest.json"
if [ "$dry_run" != "true" ]; then
  mkdir -p "$manifest_dir"
  {
    printf '{\n'
    printf '  "schemaVersion": 1,\n'
    printf '  "updatedAtUtc": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '  "updater": "update-ai-sdlc.sh",\n'
    printf '  "managedFiles": [\n'
    first="true"
    sort -u "$manifest_files" | while IFS= read -r rel; do
      [ -n "$rel" ] || continue
      if [ "$first" = "true" ]; then first="false"; else printf ",\n"; fi
      escaped=$(printf "%s" "$rel" | sed 's/\\/\\\\/g; s/"/\\"/g')
      printf '    "%s"' "$escaped"
    done
    printf '\n  ],\n'
    printf '  "protectedUpdateFiles": [\n'
    printf '    "AGENTS.md",\n'
    printf '    "tools/ai-sdlc/config/project-profile.yaml",\n'
    printf '    "tools/ai-sdlc/config/context_memory.yaml",\n'
    printf '    "tools/ai-sdlc/config/integrations.yaml",\n'
    printf '    "tools/ai-sdlc/config/token_budget.yaml",\n'
    printf '    "tools/ai-sdlc/config/execution_lanes.yaml",\n'
    printf '    "tools/ai-sdlc/config/mcp_servers.example.yaml"\n'
    printf '  ],\n'
    printf '  "generatedDirectories": [".sdlc/local-pipeline", ".sdlc/live", ".sdlc/approvals", ".sdlc/task-contracts", ".sdlc/task-queue", ".sdlc/handoffs", ".sdlc/reopen-policy", ".sdlc/approval-gates", ".sdlc/memory-index", ".sdlc/memory-lifecycle"]\n'
    printf '}\n'
  } > "$manifest_path"
fi

rm -f "$manifest_files"

cat <<EOF
{
  "targetRoot": "$target_dir",
  "sourceRoot": "$source_dir",
  "passed": true,
  "dryRun": $dry_run,
  "forceConfigs": $force_configs,
  "includeAgents": $include_agents,
  "includeGitHub": $include_github,
  "manifestPath": "$manifest_path",
  "updatedCount": $updated_count,
  "stagedForReviewCount": $staged_count,
  "unchangedCount": $unchanged_count
}
EOF
