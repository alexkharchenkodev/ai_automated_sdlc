# Canonical Naming Rules

Project-specific naming conventions live in `tools/ai-sdlc/config/project-profile.yaml`. These universal rules apply everywhere unless the profile states a stricter convention.

## Core Rules

- Use explicit, domain-meaningful names.
- Avoid abbreviations unless they are standard in the target codebase.
- Prefer names that describe responsibility, not implementation detail.
- Avoid generic names such as `Helper`, `Utils`, `Manager`, `Base`, `Thing`, and `DataObject` unless already established by the codebase.
- Match the naming style already used in the touched files.

## Tests

- Test names should describe behavior.
- Prefer focused deterministic tests for domain or contract logic.
- Use the test naming convention defined by the target stack profile.

## Content And Data

- ID/file naming should follow the profile.
- Do not invent new IDs, tags, schema fields, API routes, or statuses outside the existing model without an explicit schema/contract change.
