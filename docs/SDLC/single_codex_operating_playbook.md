# Single-Codex Operating Playbook

This playbook defines how one AI coding session runs the AI SDLC when no external agent clients are used.

The AI is the Lead Orchestrator. SDLC roles are used as lenses, evidence contracts, and review passes inside the same thread.

## Default Role Loop

1. Intake lens
   - Normalize the request.
   - Identify the user's explicit primary target.
   - Read the project profile.
   - List likely changed areas and expected output.

2. BA lens
   - Convert the request into acceptance criteria.
   - Classify complexity as low, medium, or high.
   - State uncertainties early.
   - Identify existing systems, data, and reusable capabilities.
   - Identify non-goals and protected surfaces.

3. Architecture and risk lens
   - Check boundaries listed in the project profile.
   - Check determinism, data contracts, security, performance, and release risk.
   - Decide whether human approval is required.

4. Design lens
   - For user-facing work, check states, empty/error paths, accessibility, and handoff rules.
   - For visual/reference work, define a visual rubric and evidence plan.

5. Engineering lens
   - Edit the smallest safe set of files.
   - Follow existing project patterns before adding abstractions.
   - Preserve unrelated user changes.

6. Review lens
   - Inspect for regressions, missing tests, boundary violations, and stale docs.

7. QA lens
   - Run the narrowest meaningful validation first.
   - Escalate to broader validation when shared behavior or release gates are touched.

8. Release lens
   - Confirm evidence, residual risk, and next step.

## Pre-Implementation Discovery Gate

Before coding a non-trivial feature, screen, generator, visual style, gameplay rule, content schema, API contract, infrastructure change, or SDLC tooling change, capture:

- primary target and context-only reference areas
- complexity and complexity reasons
- uncertainties and why they matter
- existing systems and data relevant to the request
- desired behavior mapped to reusable project capabilities
- likely owner files/functions
- non-goals and protected surfaces
- acceptance criteria
- verification evidence

The discovery brief is not implementation approval for high-risk work or when the user asked to discuss/check first.

## When To Stop

Stop and ask only when:

- a human approval gate is blocking policy execution
- the task requires a secret, account action, paid service, or external permission
- a product/design decision materially changes scope
- local context contradicts the user's request
- continuing would require reverting user work

Otherwise, proceed autonomously and keep the user updated.
