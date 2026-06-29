# Automated Local AI SDLC Pipeline

The portable pipeline turns a changed-file list into local SDLC evidence.

## Flow

```text
changed files
  -> impact report
  -> task intake report
  -> context memory report
  -> integrations readiness report
  -> validation plan
  -> selected validation report
  -> token usage estimate
  -> evidence bundle
  -> summary
```

## Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\run-ai-sdlc-pipeline.ps1 -ChangedFile "src/example.ts" -Task "Describe the change" -Pretty
```

For more than one changed file, prefer:

```powershell
git diff --name-only > changed-files.txt
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\run-ai-sdlc-pipeline.ps1 -ChangedFilesPath changed-files.txt -Task "Describe the change" -Pretty
```

## macOS/Linux

```sh
sh ./tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.sh --changed-file "src/example.ts" --task "Describe the change"
```

The shell wrapper requires PowerShell Core (`pwsh`) because the portable automation engine is implemented in PowerShell.

## First-Run Bootstrap

If build/test commands are not ready yet, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\run-ai-sdlc-pipeline.ps1 -ChangedFile "README.md" -SkipValidationExecution -Pretty
```

or:

```sh
sh ./tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.sh --changed-file "README.md" --skip-validation
```

Then edit `tools/ai-sdlc/config/project-profile.yaml` with the real build, test, lint, source-root, and protected-surface settings.

## Outputs

Reports are written under `.sdlc/local-pipeline/` by default:

- `sdlc-impact-report.json`
- `sdlc-task-intake-report.json`
- `sdlc-context-memory-report.json`
- `sdlc-integrations-report.json`
- `sdlc-impacted-tests.json`
- `sdlc-rollback-plan.json`
- `sdlc-validation-plan.json`
- `sdlc-selected-validation-report.json`
- `sdlc-safe-change-report.json`
- `sdlc-token-usage-report.json`
- `sdlc-evidence-bundle.json`
- `sdlc-summary.json`

Generated reports should normally be reviewed locally and archived intentionally. Do not copy reports from another project.
