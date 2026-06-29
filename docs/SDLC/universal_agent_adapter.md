# Universal AI Agent Adapter

This SDLC baseline is designed around a file protocol rather than one AI vendor.

Any AI client can participate when it can:

- read repository instructions
- inspect files
- edit files when allowed
- run local scripts or ask the user to run them
- write role events through `write-role-event.ps1`

## Codex

Codex should read `AGENTS.md`, the project profile, and the SDLC docs. It can run the orchestrator and emit role events directly while working.

## Claude

Claude-style coding agents can follow the same protocol through project instructions. Add a short `CLAUDE.md` that points to:

```text
AGENTS.md
tools/ai-sdlc/config/project-profile.yaml
docs/SDLC/README.md
```

## GitHub Copilot

Copilot can use the rules as repository instructions and can reference the scripts. Depending on the host IDE, the user may need to run the scripts manually from the terminal.

## Other Agents

Other agents should treat this as the contract:

1. Read the project profile.
2. Emit an `intake` event.
3. Produce or update role artifacts.
4. Emit role events on transitions.
5. Run validation and evidence scripts.
6. Stop when HITL gates require human approval.

## Role Flow

The role order lives in:

```text
tools/ai-sdlc/config/role_flow.yaml
```

Agents may skip roles only when they emit a `skipped` event with a reason.
