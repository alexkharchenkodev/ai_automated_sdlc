#!/usr/bin/env sh
set -eu

target="."
profile="generic"
force="false"

usage() {
  echo "Usage: sh install-ai-sdlc.sh [--target PATH] [--profile NAME] [--force]"
  echo "Profiles: generic, godot-csharp, web-node, ios-swift, android-kotlin, backend-dotnet"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      target="$2"
      shift 2
      ;;
    --profile)
      profile="$2"
      shift 2
      ;;
    --force)
      force="true"
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

script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd -P)
target_dir=$(mkdir -p "$target" && CDPATH= cd "$target" && pwd -P)
profile_path="$script_dir/profiles/$profile.yaml"

if [ ! -f "$profile_path" ]; then
  echo "Profile '$profile' was not found." >&2
  echo "Available profiles:" >&2
  find "$script_dir/profiles" -name '*.yaml' -type f -exec basename {} .yaml \; | sort >&2
  exit 1
fi

copied_count=0
skipped_count=0
copied_list="${TMPDIR:-/tmp}/ai-sdlc-copied-$$.txt"
skipped_list="${TMPDIR:-/tmp}/ai-sdlc-skipped-$$.txt"
: > "$copied_list"
: > "$skipped_list"

copy_file_if_allowed() {
  src="$1"
  dest="$2"
  dest_dir=$(dirname "$dest")
  mkdir -p "$dest_dir"

  if [ -f "$dest" ] && [ "$force" != "true" ]; then
    skipped_count=$((skipped_count + 1))
    printf "%s\n" "$dest" >> "$skipped_list"
    return 0
  fi

  cp "$src" "$dest"
  copied_count=$((copied_count + 1))
  printf "%s\n" "$dest" >> "$copied_list"
}

copy_tree_if_allowed() {
  src_root="$1"
  dest_root="$2"

  if [ ! -d "$src_root" ]; then
    echo "Missing export source directory: $src_root" >&2
    exit 1
  fi

  (cd "$src_root" && find . -type f) | while IFS= read -r relative; do
    src="$src_root/$relative"
    dest="$dest_root/$relative"
    copy_file_if_allowed "$src" "$dest"
  done
}

# Run tree copies without relying on subshell counter mutation.
copy_tree_portable() {
  src_root="$1"
  dest_root="$2"
  tmp_list="${TMPDIR:-/tmp}/ai-sdlc-copy-list-$$.txt"
  (cd "$src_root" && find . -type f) > "$tmp_list"
  while IFS= read -r relative; do
    src="$src_root/$relative"
    dest="$dest_root/$relative"
    copy_file_if_allowed "$src" "$dest"
  done < "$tmp_list"
  rm -f "$tmp_list"
}

copy_tree_portable "$script_dir/docs" "$target_dir/docs"
copy_tree_portable "$script_dir/tools" "$target_dir/tools"
copy_tree_portable "$script_dir/dashboard" "$target_dir/dashboard"
copy_tree_portable "$script_dir/github" "$target_dir/.github"
copy_file_if_allowed "$profile_path" "$target_dir/tools/ai-sdlc/config/project-profile.yaml"
copy_file_if_allowed "$script_dir/AGENTS.md.template" "$target_dir/AGENTS.md"

manifest_dir="$target_dir/.sdlc"
manifest_path="$manifest_dir/ai-sdlc-install-manifest.json"
mkdir -p "$manifest_dir"

json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

write_json_array_from_paths() {
  list_path="$1"
  first="true"
  while IFS= read -r absolute_path; do
    [ -n "$absolute_path" ] || continue
    relative_path=${absolute_path#"$target_dir"/}
    relative_path=$(printf "%s" "$relative_path" | sed 's#\\#/#g')
    if [ "$first" = "true" ]; then
      first="false"
    else
      printf ",\n"
    fi
    printf '    "%s"' "$(json_escape "$relative_path")"
  done < "$list_path"
}

{
  printf '{\n'
  printf '  "schemaVersion": 1,\n'
  printf '  "installedAtUtc": "%s",\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '  "installer": "install-ai-sdlc.sh",\n'
  printf '  "profile": "%s",\n' "$(json_escape "$profile")"
  printf '  "managedFiles": [\n'
  write_json_array_from_paths "$copied_list"
  printf '\n  ],\n'
  printf '  "skippedFiles": [\n'
  write_json_array_from_paths "$skipped_list"
  printf '\n  ],\n'
  printf '  "protectedUpdateFiles": [\n'
  printf '    "AGENTS.md",\n'
  printf '    "tools/ai-sdlc/config/project-profile.yaml",\n'
  printf '    "tools/ai-sdlc/config/context_memory.yaml",\n'
  printf '    "tools/ai-sdlc/config/integrations.yaml",\n'
  printf '    "tools/ai-sdlc/config/token_budget.yaml",\n'
  printf '    "tools/ai-sdlc/config/mcp_servers.example.yaml"\n'
  printf '  ],\n'
  printf '  "generatedDirectories": [\n'
  printf '    ".sdlc/local-pipeline",\n'
  printf '    ".sdlc/live",\n'
  printf '    ".sdlc/approvals"\n'
  printf '  ]\n'
  printf '}\n'
} > "$manifest_path"

rm -f "$copied_list" "$skipped_list"

cat <<EOF
{
  "targetRoot": "$target_dir",
  "profile": "$profile",
  "copiedCount": $copied_count,
  "skippedCount": $skipped_count,
  "manifestPath": "$manifest_path",
  "force": $force,
  "nextSteps": [
    "Edit tools/ai-sdlc/config/project-profile.yaml for the target repository.",
    "Edit tools/ai-sdlc/config/context_memory.yaml, integrations.yaml, and token_budget.yaml.",
    "Read AGENTS.md and docs/SDLC/README.md before starting AI-assisted work.",
    "Run tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.sh to generate fresh SDLC evidence on macOS/Linux.",
    "Run tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.sh --open-dashboard to view live role progress.",
    "Use update-ai-sdlc.sh from a newer framework checkout to update this AI SDLC baseline.",
    "Use uninstall-ai-sdlc.sh --dry-run first if you need to remove this AI SDLC baseline later.",
    "Review .github/workflows/ai-sdlc.yml before enabling strict project validation in CI.",
    "Do not copy old sdlc-*.json/md reports from another repository."
  ]
}
EOF
