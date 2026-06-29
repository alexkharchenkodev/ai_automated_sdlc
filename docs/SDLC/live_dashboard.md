# Live Role Dashboard

The portable AI SDLC dashboard visualizes which role is active, what it is doing, and which artifacts have been produced.
It also exposes a `Config` modal and a `Project Memory` section for ADR, RAG, GraphRAG, and code-search readiness.

## Files

Runtime files are generated under `.sdlc/live/`:

- `events.jsonl`: append-only role event log
- `state.json`: latest role state
- `dashboard/index.html`: self-refreshing local dashboard app
- `dashboard/runtime-state.js`: browser-readable snapshot of state, events, profile, summary, safety, context memory, integrations, and token report
- `dashboard/app.js`: local UI for role flow, config summary, project memory, artifacts, and event logs

These are generated evidence files. Do not copy them from another project.

## Start Dashboard

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\start-ai-sdlc-dashboard.ps1 -Pretty
```

macOS/Linux:

```sh
sh ./tools/ai-sdlc/scripts/start-ai-sdlc-dashboard.sh
```

## Run Visible Orchestration

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\run-ai-sdlc-orchestrator.ps1 -ChangedFile "src/example.ts" -Task "Add button action" -OpenDashboard -Pretty
```

For more than one changed file, prefer:

```powershell
git diff --name-only > changed-files.txt
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\run-ai-sdlc-orchestrator.ps1 -ChangedFilesPath changed-files.txt -Task "Add button action" -OpenDashboard -Pretty
```

macOS/Linux:

```sh
sh ./tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.sh --changed-file "src/example.ts" --task "Add button action" --open-dashboard
```

## Event Schema

Each event is one JSON object:

```json
{
  "schemaVersion": 1,
  "runId": "run-20260629-120000",
  "timeUtc": "2026-06-29T12:00:00Z",
  "role": "engineering",
  "status": "running",
  "message": "Editing scoped files",
  "artifacts": ["src/example.ts"]
}
```

Statuses:

- `pending`
- `running`
- `completed`
- `skipped`
- `waiting`
- `blocked`
- `failed`

## Agent Usage

Any AI client that can run commands can emit role progress:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\write-role-event.ps1 -Role engineering -Status running -Message "Editing scoped files" -Artifact "src/example.ts" -Pretty
```

The dashboard is intentionally file-based. It does not require a database, network service, or vendor-specific agent runtime.
