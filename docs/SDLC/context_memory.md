# Context And Memory Configuration

The portable AI SDLC framework separates memory policy from implementation.
Configure expected context sources in:

```text
tools/ai-sdlc/config/context_memory.yaml
```

## Provider Types

- `adr`: architecture decision records and durable design decisions.
- `rag`: local documentation and repository knowledge that can be retrieved by an AI client.
- `graph_rag`: optional repository graph, dependency graph, or knowledge graph context.
- `code_search`: direct repository search before inventing new behavior.
- `issue_tracker`: external tracker context exposed through an integration such as Jira.

Providers can be enabled or disabled per project. The portable scripts do not
build indexes or contact external services. They generate a readiness report:

```text
.sdlc/local-pipeline/sdlc-context-memory-report.json
```

AI clients should use this report as a contract: if a provider is enabled, the
agent should check that source before proposing new code or architecture.

## Recommended Defaults

Keep `adr`, `rag`, and `code_search` enabled for most projects. Enable
`graph_rag` only after the target project has a real graph source or indexing
pipeline. Enable `issue_tracker` only when the tracker integration is ready.
