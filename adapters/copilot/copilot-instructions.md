# AI SDLC Copilot Adapter

Use this file as a Copilot custom instructions seed.

## Workflow

- Treat `tools/ai-sdlc/scripts/ai-sdlc.ps1` as the control-plane CLI.
- For a non-trivial task, create a task contract before implementation.
- When an executor work order exists, complete the requested role and submit artifacts back into the task contract.
- Do not move from one role to the next until the matching handoff gate has passed.
- If review, architecture, UX, tests, or policy finds a gap, emit a reopen event with a concrete reason.
- Keep evidence under `.sdlc/` and link it from the final answer or PR.

## Minimum Commands

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 doctor -Pretty
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 new-task -Title "Describe task" -Pretty
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 queue -Pretty
```
