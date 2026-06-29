# Role Contracts

Each role owns one type of judgment and one set of artifacts.

## BA

Owns task clarity.

Outputs:

- BA brief
- complexity classification
- acceptance criteria
- existing system and data discovery
- protected surfaces and non-goals
- edge cases
- open questions

## Design

Owns user flow, interaction behavior, content clarity, and visual acceptance when applicable.

Outputs:

- design brief
- state map
- component or screen inventory
- accessibility/input notes
- visual rubric for reference-matching work

## Design Review Lens

Owns consistency and usability risk. This is usually applied inside `design` and `code_review` instead of becoming a separate required dashboard role.

Outputs:

- findings ordered by severity
- reuse notes
- accessibility/input concerns
- approval or blockers

## Engineering

Owns implementation within active architecture.

Outputs:

- implementation plan
- code changes
- tests
- validation evidence

## Code Review

Owns defect, regression, and boundary risk.

Outputs:

- findings ordered by severity
- missing test notes
- residual risk
- approval or blockers

## Test Planning

Owns validation selection.

Outputs:

- test scope
- build/test/lint command selection
- manual QA needs
- screenshot/video requirements
- skip reasons when validation cannot run

## Test Execution

Owns validation evidence.

Outputs:

- command output summary
- automated test evidence
- manual QA report when needed
- failure repro artifacts
- residual risk

## Automation QA Lens

Owns repeatable validation. This lens is applied inside `test_planning` and `test_execution`.

Outputs:

- test additions
- automation scenarios
- validation report
- failure repro artifacts

## Manual QA Lens

Owns human-observed product quality. This lens is applied inside `test_execution` when screenshots, manual flows, device checks, or exploratory validation are required.

Outputs:

- manual test report
- screenshots/video when useful
- known issues
- release recommendation

## Evidence

Owns the final machine-readable proof bundle.

Outputs:

- evidence bundle
- compliance decision
- approval records
- reopen summary
- memory and context reports
- residual risk

## Release Lens

Owns readiness to ship. This lens is applied inside `evidence` and `done`.

Outputs:

- release notes
- validation summary
- release confidence
- known risks
