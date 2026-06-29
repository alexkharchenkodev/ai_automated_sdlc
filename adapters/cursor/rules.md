# AI SDLC Cursor Adapter

Use this adapter with Cursor project rules.

- Use `tools/ai-sdlc/scripts/ai-sdlc.ps1` or `tools/ai-sdlc/scripts/ai-sdlc.sh` as the main SDLC entrypoint.
- Record task contracts in `.sdlc/task-contracts`.
- Use `.sdlc/executor/work-orders` as role assignments when the real executor is active.
- Submit role outputs with `submit-role-artifact.ps1`.
- Emit role progress to the live dashboard through `write-role-event.ps1`.
- Validate role handoffs with `verify-handoff-gate.ps1`.
- Validate reopen loops with `verify-reopen-policy.ps1`.
- Validate human approvals with `verify-approval-gate.ps1`.
- End with an evidence bundle and a concise residual risk note.
