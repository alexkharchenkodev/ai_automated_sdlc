# AI SDLC Overview

AI work must move through a controlled lifecycle with explicit artifacts, validation, review, traceability, and human gates.

## Operating Model

Default local execution uses one accountable AI coding session as the Lead Orchestrator. The AI applies BA, design, engineering, QA, review, release, and SDLC lenses inside one workflow unless the user explicitly asks for delegation.

```text
Request or ticket
  -> Intake
  -> BA
  -> Design
  -> Design Review
  -> Engineering
  -> Code Review
  -> Automation QA
  -> Manual QA
  -> Release
  -> Traceability and backlog
```

## Core Principles

- The project profile defines active stack, source roots, validation commands, and protected surfaces.
- No lifecycle transition happens without the required artifact.
- No merge or release happens without validation evidence.
- High-risk changes require reviewer or human escalation.
- Human approval is required for destructive, security-sensitive, schema/data-contract, release, paid-service, and ambiguous product decisions.
- Generated evidence belongs to the target repo and should not be copied from another project.

## Primary Artifacts

- Task intake or ticket brief.
- BA brief.
- Design brief or design review notes when user-facing behavior changes.
- Implementation plan.
- Code review report.
- QA test plan.
- Automation evidence.
- Manual QA report when needed.
- Release note.
- Traceability record.
