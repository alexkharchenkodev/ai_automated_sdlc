# Live Role Dashboard

The portable AI SDLC dashboard visualizes which task and role are active, what they are doing, which execution lane is selected, whether compliance passed, and which artifacts have been produced.
It also exposes a `Config` modal and a `Project Memory` tab for ADR, RAG, GraphRAG, and code-search readiness.

## Files

Runtime files are generated under `.sdlc/live/`:

- `events.jsonl`: append-only task and role event log
- `state.json`: latest task queue and role state
- `dashboard/index.html`: local dashboard shell
- `dashboard/runtime-state.js`: browser-readable snapshot of state, events, profile, summary, lane, compliance, safety, context memory, memory previews, integrations, and token report
- `dashboard/app.js`: local UI for the task queue, role graph, config summary, project memory, artifacts, grouped event logs, and async state polling

These are generated evidence files. Do not copy them from another project.

The dashboard does not reload the full page on each update. It polls `runtime-state.js`
every three seconds and updates the rendered sections in place, so selected text,
the active Project Memory tab, and open modal state are preserved during live runs.

## Task Queue Model

Events can belong to a batch and task:

- `runId`: one local dashboard/orchestrator run
- `batchId`: a group of related tasks, such as a BA split of a larger request
- `taskId`: one executable task inside the batch
- `taskTitle`: user-readable task name
- `taskOrder`: queue ordering hint
- `taskStatus`: task-level state when known

The dashboard groups events by `taskId`. The `Tasks` tab shows the queue,
current task, planned work, completed work, blocked work, task-scoped role flow,
task events, and task artifacts. The `Events` tab shows collapsible task groups
instead of one flat stream.

If an agent does not provide task metadata, `write-role-event.ps1` keeps backward
compatibility by assigning the event to `task-local`.

## Project Memory Preview

The `Memory` tab reads the context-memory report and shows configured ADR, RAG,
GraphRAG, code-search, or integration sources. If a provider is disabled or a
source is unavailable, the dashboard explains why the content cannot be shown.

For local files and directories, `write-role-event.ps1` emits a bounded preview
into `AI_SDLC_MEMORY_CONTENT` inside `dashboard/runtime-state.js`:

- file sources include the first characters of the file
- directory sources include a limited set of text-like files and short snippets
- generated live output, `.git`, build folders, and dependency folders are skipped
- previews stay inside the project root

This is for visibility only. The framework still expects real RAG, GraphRAG, or
issue-tracker indexing to be supplied by the configured project/tooling.

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
  "artifacts": ["src/example.ts"],
  "batchId": "batch-20260629-001",
  "taskId": "task-003",
  "taskTitle": "Add button action",
  "taskStatus": "running",
  "taskOrder": 3
}
```

Framework-owned dashboard/bootstrap events use `role: "system"`. They are not
SDLC role work and should be interpreted as local dashboard lifecycle messages.

Statuses:

- `pending`
- `running`
- `completed`
- `skipped`
- `waiting`
- `blocked`
- `failed`

Task statuses use the same operational vocabulary plus queue-level values:

- `planned`
- `ready`
- `running`
- `waiting`
- `completed`
- `blocked`
- `failed`
- `skipped`

## Agent Usage

Any AI client that can run commands can emit role progress:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\write-role-event.ps1 -Role engineering -Status running -Message "Editing scoped files" -Artifact "src/example.ts" -Pretty
```

Task-aware event:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\write-role-event.ps1 -RunId "run-20260629-120000" -BatchId "batch-20260629-001" -TaskId "task-003" -TaskTitle "Add button action" -TaskOrder 3 -TaskStatus running -Role engineering -Status running -Message "Editing scoped files" -Artifact "src/example.ts" -Pretty
```

The dashboard is intentionally file-based. It does not require a database, network service, or vendor-specific agent runtime.
