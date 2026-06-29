# AI SDLC Codex Adapter

Use this adapter when a project is driven from Codex.

## Required Startup

1. Read the project `AGENTS.md`.
2. Run or review `tools/ai-sdlc/scripts/ai-sdlc.ps1 doctor`.
3. Create or load a task contract before non-trivial implementation.
4. Emit live role events with `tools/ai-sdlc/scripts/write-role-event.ps1`.

## Operating Loop

- Discovery and BA must produce a task contract under `.sdlc/task-contracts`.
- Architecture, memory reuse, design, engineering, review, test, and evidence phases must attach artifacts.
- Use `tools/ai-sdlc/scripts/verify-handoff-gate.ps1` before moving between roles.
- Use `tools/ai-sdlc/scripts/verify-reopen-policy.ps1` after any reopen loop.
- Use `tools/ai-sdlc/scripts/write-evidence-bundle.ps1` before final handoff.

## Codex Notes

- Prefer repo-local commands and existing scripts over invented workflows.
- Keep user-owned changes intact.
- If a gate blocks, report the reason and the next smallest unblock step.

