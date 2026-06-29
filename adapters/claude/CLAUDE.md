# AI SDLC Claude Adapter

Claude should use the AI SDLC framework as a visible delivery control plane.

## Rules

- Start with project discovery and task contract creation for medium or high complexity work.
- If `.sdlc/executor/work-orders/` contains a role work order, treat it as the current role assignment.
- Submit completed role outputs through `submit-role-artifact.ps1` or `ai-sdlc submit-artifact`.
- Use handoff gates between BA, architecture, memory reuse, design, engineering, review, test, and evidence.
- Write explicit reopen reasons when a role sends work backward.
- Generate an evidence bundle before claiming completion.
- Respect project-local rules first; this adapter is a portable supplement.

## Useful Commands

```sh
sh tools/ai-sdlc/scripts/ai-sdlc.sh doctor
sh tools/ai-sdlc/scripts/ai-sdlc.sh dashboard --no-open
sh tools/ai-sdlc/scripts/ai-sdlc.sh queue
```
