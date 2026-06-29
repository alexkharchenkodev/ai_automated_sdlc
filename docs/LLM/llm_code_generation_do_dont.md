# LLM Code Generation Do/Don't

Use this as the lean governance layer for AI-assisted implementation. Project-specific stack rules live in `tools/ai-sdlc/config/project-profile.yaml`.

## Do

- Follow the project profile first.
- Honor the user's explicit target first.
- For non-trivial implementation, run the pre-implementation discovery gate before edits.
- Classify complexity before choosing workflow.
- State uncertainty immediately when the answer or approach is unclear.
- Map desired behavior to existing reusable project capabilities before inventing new code.
- Keep edits scoped to owner files and protected surfaces.
- Add focused deterministic tests for non-trivial behavior changes.
- Use the validation commands listed in the project profile.
- Preserve unrelated user changes.

## Don't

- Do not replace a user-specified target with the default project area.
- Do not start file edits after a brief when a confirmation gate applies.
- Do not treat critique, screenshots, clarifications, or agreement with analysis as implementation approval after a confirmation gate.
- Do not use an approval with added constraints as permission for unrelated rewrites.
- Do not guess when the task model is uncertain or non-standard.
- Do not invent new systems, schema fields, API contracts, statuses, or workflow steps before checking existing capabilities.
- Do not hide runtime failures or swallow exceptions.
- Do not commit generated evidence from another project as if it belongs to the target repo.
