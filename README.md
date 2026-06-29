# Portable AI SDLC Export

This folder is a portable starter kit for AI SDLC rules, with project-specific product, engine, and repository assumptions removed.

Use it to install a reusable AI SDLC baseline into another repository, then adapt the copied `tools/ai-sdlc/config/project-profile.yaml` to the target stack.

## What This Exports

- `docs/SDLC`: universal operating model, gates, role contracts, evidence rules, and templates.
- `docs/LLM`: lean AI coding and naming guardrails that point to the project profile instead of a fixed engine or language.
- `tools/ai-sdlc/config`: portable profile and gate configuration examples.
- `dashboard`: local static dashboard for role flow, safety, integrations, context memory, and token estimates.
- `profiles`: ready-to-copy profiles for common stacks.
- `.github`: portable PR template and AI SDLC evidence workflow.
- `install-ai-sdlc.ps1`: Windows/PowerShell installer.
- `install-ai-sdlc.sh`: macOS/Linux shell installer.
- `update-ai-sdlc.ps1` / `update-ai-sdlc.sh`: update an installed AI SDLC baseline from a newer framework checkout.
- `uninstall-ai-sdlc.ps1` / `uninstall-ai-sdlc.sh`: remove installed AI SDLC managed files from a target repo.

## What This Does Not Export

Do not copy generated project artifacts as a reusable baseline:

- `.sdlc/`
- `sdlc-*.json`
- `sdlc-*.md`
- `sdlc-artifacts/`
- screenshots, RAG indexes, project graphs, temporary reports

Those files describe one repository at one point in time. New projects should generate their own evidence.

## Install On Windows

```powershell
powershell -ExecutionPolicy Bypass -File ".\install-ai-sdlc.ps1" -TargetRoot "<target-project-path>" -Profile web-node
```

Use `-Force` only when you intentionally want to overwrite existing AI SDLC files in the target repo.

## Install On macOS Or Linux

```sh
sh "./install-ai-sdlc.sh" --target "<target-project-path>" --profile web-node
```

Use `--force` only when you intentionally want to overwrite existing AI SDLC files in the target repo.

Install writes a manifest to the target repository:

```text
.sdlc/ai-sdlc-install-manifest.json
```

The uninstall command uses that manifest to remove only files that were actually installed by AI SDLC.

## Update An Installed AI SDLC

Pull or download the newer framework version, then update a target project.

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File ".\update-ai-sdlc.ps1" -TargetRoot "<target-project-path>"
```

macOS/Linux:

```sh
sh "./update-ai-sdlc.sh" --target "<target-project-path>"
```

By default update refreshes framework-owned docs, scripts, and dashboard files.
Project-specific files are protected:

```text
AGENTS.md
tools/ai-sdlc/config/project-profile.yaml
tools/ai-sdlc/config/context_memory.yaml
tools/ai-sdlc/config/integrations.yaml
tools/ai-sdlc/config/token_budget.yaml
tools/ai-sdlc/config/mcp_servers.example.yaml
```

When a protected file already exists, update writes the new framework copy as
`<file>.new` for review instead of overwriting the user's configuration. Use
`-ForceConfigs` or `--force-configs` only when you intentionally want to replace
configured AI SDLC files. Use `-IncludeGitHub` / `--include-github` to update
the optional GitHub workflow files, and `-IncludeAgents` / `--include-agents` to
stage a new `AGENTS.md`.

Preview an update without writing files:

```powershell
powershell -ExecutionPolicy Bypass -File ".\update-ai-sdlc.ps1" -TargetRoot "<target-project-path>" -DryRun
```

## Uninstall AI SDLC

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File ".\uninstall-ai-sdlc.ps1" -TargetRoot "<target-project-path>" -DryRun
powershell -ExecutionPolicy Bypass -File ".\uninstall-ai-sdlc.ps1" -TargetRoot "<target-project-path>"
```

macOS/Linux:

```sh
sh "./uninstall-ai-sdlc.sh" --target "<target-project-path>" --dry-run
sh "./uninstall-ai-sdlc.sh" --target "<target-project-path>"
```

Generated evidence under `.sdlc/local-pipeline`, `.sdlc/live`, and
`.sdlc/approvals` is kept by default. Add `-IncludeGenerated` or
`--include-generated` only when you intentionally want to remove generated AI
SDLC runtime artifacts too.

## Available Profiles

- `generic`
- `godot-csharp`
- `web-node`
- `ios-swift`
- `android-kotlin`
- `backend-dotnet`

Profiles are starting points, not law. After install, edit:

```text
tools/ai-sdlc/config/project-profile.yaml
```

## Run The Automated Local SDLC Pipeline

After installing and adjusting `project-profile.yaml`, run the pipeline for changed files.

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\ai-sdlc\scripts\run-ai-sdlc-pipeline.ps1" -ChangedFile "src/example.ts" -Task "Describe the change" -Pretty
```

For multiple changed files, prefer a file list:

```powershell
git diff --name-only > changed-files.txt
powershell -ExecutionPolicy Bypass -File ".\tools\ai-sdlc\scripts\run-ai-sdlc-pipeline.ps1" -ChangedFilesPath changed-files.txt -Task "Describe the change" -Pretty
```

macOS/Linux:

```sh
sh "./tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.sh" --changed-file "src/example.ts" --task "Describe the change"
```

The pipeline writes fresh evidence under:

```text
.sdlc/local-pipeline/
  sdlc-impact-report.json
  sdlc-task-intake-report.json
  sdlc-context-memory-report.json
  sdlc-integrations-report.json
  sdlc-impacted-tests.json
  sdlc-rollback-plan.json
  sdlc-validation-plan.json
  sdlc-selected-validation-report.json
  sdlc-safe-change-report.json
  sdlc-token-usage-report.json
  sdlc-evidence-bundle.json
  sdlc-summary.json
```

Use `-SkipValidationExecution` or `--skip-validation` when first bootstrapping a project whose build/test commands are not ready yet.

## Visualize Role Progress

Start a local live dashboard:

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\ai-sdlc\scripts\start-ai-sdlc-dashboard.ps1" -Pretty
```

Then run the visible orchestrator:

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\ai-sdlc\scripts\run-ai-sdlc-orchestrator.ps1" -ChangedFile "src/example.ts" -Task "Add button action" -OpenDashboard -Pretty
```

For multiple changed files:

```powershell
git diff --name-only > changed-files.txt
powershell -ExecutionPolicy Bypass -File ".\tools\ai-sdlc\scripts\run-ai-sdlc-orchestrator.ps1" -ChangedFilesPath changed-files.txt -Task "Add button action" -OpenDashboard -Pretty
```

macOS/Linux:

```sh
sh "./tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.sh" --changed-file "src/example.ts" --task "Add button action" --open-dashboard
```

The dashboard writes and reads:

```text
.sdlc/live/events.jsonl
.sdlc/live/state.json
.sdlc/live/index.html
```

Any AI client can update the same dashboard by emitting role events with `write-role-event.ps1`.

## Configure Context, Memory, Tokens, And Integrations

After install, tune these project-level files:

```text
tools/ai-sdlc/config/context_memory.yaml
tools/ai-sdlc/config/integrations.yaml
tools/ai-sdlc/config/token_budget.yaml
tools/ai-sdlc/config/mcp_servers.example.yaml
```

The defaults are offline and safe. Jira, GitHub, and Linear are present as MCP
examples but disabled until the target project opts in. ADR/RAG/code search are
enabled as local context providers; GraphRAG is disabled until a real graph
source exists. Token usage is an approximate local estimate for context size,
not a billing record.

## Safety Gates

The framework includes a safe-change gate. Security-sensitive, schema/API contract, and high-risk changes require approval records before the evidence bundle can proceed.

Create approval records deliberately:

```powershell
powershell -ExecutionPolicy Bypass -File ".\tools\ai-sdlc\scripts\write-approval-record.ps1" -Scope schema_or_api_contract_change -Approver "name" -Reason "approved contract change" -Pretty
```

The safety gate also generates impacted-test suggestions and rollback plans.

## GitHub Automation

The installer also copies:

```text
.github/PULL_REQUEST_TEMPLATE.md
.github/workflows/ai-sdlc.yml
```

The workflow builds a changed-file list, runs the portable pipeline, and uploads `.sdlc/local-pipeline` as an artifact. On PR/push it defaults to evidence generation without executing project validation commands so a newly installed profile does not break the first CI run. Review `project-profile.yaml` and the workflow before enabling strict CI validation for release decisions.

## Recommended Adoption Steps

1. Install the baseline into the target repo.
2. Edit `project-profile.yaml` with real source roots, build commands, test commands, design/tracker/CI tools, and protected surfaces.
3. Edit `context_memory.yaml`, `integrations.yaml`, and `token_budget.yaml`.
4. Run the automated local SDLC pipeline once with `--skip-validation` or `-SkipValidationExecution` to verify evidence generation.
5. Add project-specific docs under `docs/LLM` only when the target stack needs them.
6. Keep core gates universal; put stack-specific rules in the profile.
7. Generate fresh SDLC artifacts in the target repo instead of copying old reports.

## Portability Rule

Core SDLC documents should not mention a concrete product, engine, repository path, framework, or CI command unless they are examples. Put those details into a profile.
