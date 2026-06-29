# Safe Change Policy

The AI SDLC framework should make development faster without silently increasing defect risk.

## Required Safety Evidence

Every automated run should produce:

- `sdlc-impact-report.json`
- `sdlc-task-intake-report.json`
- `sdlc-impacted-tests.json`
- `sdlc-rollback-plan.json`
- `sdlc-validation-plan.json`
- `sdlc-selected-validation-report.json`
- `sdlc-safe-change-report.json`
- `sdlc-evidence-bundle.json`

## Blocking Conditions

`validate-safe-change.ps1` blocks when:

- required reports are missing
- selected validation failed
- risk requires a rollback plan and none exists
- impact analysis requires approval but no matching approval record exists

Approval records live under:

```text
.sdlc/approvals/
```

Create one with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\write-approval-record.ps1 -Scope security_sensitive_change -Approver "name" -Reason "why approved" -Pretty
```

Use `-Scope all` only for deliberate broad approval.

## Safety Philosophy

Low-risk code changes should stay lightweight. Security, schema/API contract, migration, release, dependency, and high-risk changes must be visible, traceable, and reversible.
