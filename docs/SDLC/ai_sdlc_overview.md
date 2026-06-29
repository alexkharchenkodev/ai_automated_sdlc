# AI SDLC Overview

AI work must move through a controlled lifecycle with explicit artifacts, validation, review, traceability, and human gates.

This framework is not just a collection of agent rules. Rules describe expected behavior; AI SDLC evidence proves what actually happened and whether the result can proceed.

## Operating Model

Default local execution uses one accountable AI coding session as the Lead Orchestrator. The AI applies BA, design, engineering, QA, review, release, and SDLC lenses inside one workflow unless the user explicitly asks for delegation.

```text
Request or ticket
  -> Intake
  -> BA
  -> Architecture
  -> Memory / Reuse
  -> Design
  -> Engineering
  -> Code Review
  -> Test Planning
  -> Test Execution
  -> Evidence Bundle
  -> Done / Handoff
```

Additional role lenses are applied inside this canonical runtime flow instead of always adding more dashboard nodes:

- Design Review is part of `design` and `code_review`.
- Automation QA and Manual QA are part of `test_planning` and `test_execution`.
- Release readiness is part of `evidence` and `done`.
- Traceability and backlog updates are evidence artifacts attached to `done`.

## Core Principles

- The project profile defines active stack, source roots, validation commands, and protected surfaces.
- No lifecycle transition happens without the required artifact.
- No merge or release happens without validation evidence.
- High-risk changes require reviewer or human escalation.
- Risk determines the execution lane: `fast`, `standard`, or `strict`.
- CI and reviewers consume the compliance verdict: `proceed`, `review_required`, or `blocked`.
- Human approval is required for destructive, security-sensitive, schema/data-contract, release, paid-service, and ambiguous product decisions.
- Generated evidence belongs to the target repo and should not be copied from another project.

## Primary Artifacts

- Task intake or ticket brief.
- BA brief.
- Architecture boundary notes.
- Memory and reuse evidence.
- Design brief or design review notes when user-facing behavior changes.
- Implementation plan.
- Code review report.
- Test plan.
- Automated or manual validation evidence.
- Evidence bundle.
- Handoff, release note, or traceability record when needed.
- Execution lane report.
- Compliance report.
