# AI SDLC Entry Point

This folder contains the portable AI SDLC operating model.

Start here:

- `ai_sdlc_overview.md` for the end-to-end lifecycle.
- `single_codex_operating_playbook.md` for one-agent orchestration.
- `agent_failure_mode_gates.md` for target, approval, uncertainty, reuse, visual, and rejection gates.
- `role_contracts.md` for BA, design, engineering, review, QA, and release outputs.
- `definition_of_ready.md` and `definition_of_done.md` for work-item quality.
- `automated_pipeline.md` for the portable local automation flow.
- `framework_doctor.md` for install/config readiness checks.
- `framework_control_plane.md` for task contracts, handoff gates, reopen policy, queue runner, memory lifecycle, approvals, adapters, and CLI.
- `real_executor.md` for work-order, external-command, and artifact-submit execution modes.
- `execution_lanes.md` for fast/standard/strict lanes and CI compliance verdicts.
- `live_dashboard.md` for role visualization and event logs.
- `safe_change_policy.md` for blockers, approval records, rollback plans, and safety evidence.
- `context_memory.md` for ADR, RAG, GraphRAG, and repository context providers.
- `integrations.md` for Jira/MCP and external integration readiness checks.
- `token_budget.md` for approximate token usage reporting.
- `universal_agent_adapter.md` for using the same protocol from Codex, Claude, Copilot, or another AI client.
- `templates/` for reusable evidence artifacts.

Project-specific values live in:

```text
tools/ai-sdlc/config/project-profile.yaml
```

Do not hard-code stack, framework, repository path, CI, tracker, or design-tool assumptions in core SDLC docs.
