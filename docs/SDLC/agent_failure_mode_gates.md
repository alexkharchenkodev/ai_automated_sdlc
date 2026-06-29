# Agent Failure Mode Gates

These gates prevent confident but wrong edits.

| Gate | Trigger | Required behavior |
| --- | --- | --- |
| Explicit target precedence | User names a folder, tool, page, file, module, or screen | Treat that named surface as the primary target. Other areas are context-only unless requested. |
| Complexity classification | Any non-trivial task | Classify `low`, `medium`, or `high` and list reasons before choosing workflow. |
| Uncertainty declaration | Answer, model, or solution path is unclear | Say what is uncertain and why it matters. Continue discovery or ask for direction. |
| Existing capability reuse | Medium/high complexity or shared behavior | Map desired behavior to existing project capabilities before proposing new code. |
| Brief is not approval | High-risk task or user asks to discuss/check first | Stop after brief and plan. Wait for explicit implementation approval. |
| Critique is not approval | User provides screenshot, critique, bug report, clarification, or extra context after a confirmation gate | Update brief or recalibration notes. Do not edit. |
| Approval plus constraints | User approves and adds reminders or limits | Restate approved scope and update acceptance criteria before editing. |
| Rejection recalibration | User rejects visual, procedural, design, or UX result | Track rejection count. After two rejections, stop automatic edits and recalibrate. |
| Evidence | User-facing, release, data-contract, or workflow output changed | Provide validation, screenshot/export, report, or other evidence appropriate to the profile. |

## Complexity Defaults

Default to `medium` or `high` when any of these are true:

- visual reference matching
- procedural or generated output
- renderer, animation, build, release, infrastructure, or pipeline changes
- prior failed attempts
- ambiguous product/design direction
- possible data model or API contract change
- multiple roles needed

## Rejection Recalibration

After one rejection:

- state what missed the target
- name the likely failed assumption
- name what still works
- propose the smallest next slice

After two rejections:

- stop automatic edits
- summarize current output, user complaints, reference target, likely root causes, preserved working parts, rejected assumptions, and 2-3 alternatives

After three rejections:

- return to BA/design review and ask for renewed direction before further edits
