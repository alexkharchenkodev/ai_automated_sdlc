# Execution Lanes And Compliance

AI SDLC is useful only when it turns project rules into repeatable checks. Execution lanes do that by scaling the process to the risk of the change.

## Lanes

- `fast`: low-risk, small scoped changes. Validation may be skipped during bootstrap, but that produces `review_required`.
- `standard`: normal feature and bug-fix work. Requires complete evidence, memory/context checks, rollback plan, validation plan, and token report.
- `strict`: high-risk, security-sensitive, schema/API, CI, dependency, or broad changes. Requires human approval when requested by the impact report and real validation execution.

The lane selector writes:

```text
.sdlc/local-pipeline/sdlc-lane-report.json
```

Project defaults live in:

```text
tools/ai-sdlc/config/execution_lanes.yaml
```

## Compliance Verdict

The compliance verifier reads the generated reports and emits one machine-readable decision:

- `proceed`: required evidence is present and gates passed.
- `review_required`: no hard blocker, but the run is not fully trustworthy, usually because validation was skipped or context/integration readiness is incomplete.
- `blocked`: a required report, approval, validation result, lane rule, safe-change gate, or token budget blocks the change.

Run it locally:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\verify-sdlc-compliance.ps1 -ReportDirectory .sdlc/local-pipeline -Pretty
```

On macOS/Linux:

```sh
sh ./tools/ai-sdlc/scripts/verify-sdlc-compliance.sh --report-directory .sdlc/local-pipeline
```

Use `-AllowReviewRequired` or `--allow-review-required` only when bootstrapping a project or when CI should fail only on hard blockers.

## Why This Is Different From Rules

Rules tell an AI agent how it should behave. Lanes and compliance prove what actually happened:

- which files were considered;
- how risky the change was;
- which lane was selected;
- which reports were required;
- whether validation was executed or skipped;
- whether approvals were present;
- whether the final state is `proceed`, `review_required`, or `blocked`.

That is the line between prompt discipline and an executable SDLC framework.
