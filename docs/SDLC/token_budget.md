# Token Budget Reporting

The portable framework includes an approximate token usage report configured in:

```text
tools/ai-sdlc/config/token_budget.yaml
```

The estimator counts changed file content and generated SDLC reports, then uses
a simple `chars_per_token` ratio. This is not a billing source of truth. It is a
guardrail for context size, cost awareness, and prompt quality.

Reports are written to:

```text
.sdlc/local-pipeline/sdlc-token-usage-report.json
```

## Decisions

- `proceed`: estimate is below the warning threshold.
- `warning`: estimate is high but can continue.
- `review_required`: context is large enough that the operator should consider
  slicing the task or reducing attached context.
- `blocked`: context is beyond the configured hard limit.

Tune thresholds per project. Smaller mobile apps can often use lower thresholds;
large backend or monorepo projects may need higher limits.
