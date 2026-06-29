# AI SDLC Framework Control Plane

This framework is useful only if it adds observable, repeatable controls around AI-assisted development. The control plane is the portable layer that makes that happen.

## 1. Task Contract

Every non-trivial task should have a machine-readable contract:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 new-task -Title "Add checkout flow" -Pretty
```

Contracts are stored in `.sdlc/task-contracts/` and contain title, target, acceptance criteria, non-goals, dependencies, approval scopes, reuse evidence, validation evidence, and residual risk.

Complex contracts must be decomposed before implementation. The decomposition gate detects broad app/screen/flow requests and blocks execution until BA creates child task contracts.

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 decompose -TaskContractPath ".sdlc/task-contracts/example.json" -Pretty
```

## 2. Role Handoff Contracts

Role transitions are verified by `verify-handoff-gate.ps1` and configured in:

```text
tools/ai-sdlc/config/handoff_gates.yaml
```

If a required field is missing, the gate returns `reopen_required` and can emit a dashboard reopen event.

## 3. Reopen Policies

Reopen loops are not failures by themselves; invisible reopen loops are the failure. Policy lives in:

```text
tools/ai-sdlc/config/reopen_policy.yaml
```

The verifier counts task reopens, role-pair loops, missing reasons, and critical reopen severity.

## 4. Real Queue Runner

`run-ai-sdlc-task-queue.ps1` processes `.sdlc/task-contracts/*.json` in order, emits live dashboard events, runs every configured handoff gate through `done`, checks approvals, verifies reopen policy, and writes a queue summary.

For production integrations, prefer the real executor:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 executor -Mode work_order -Pretty
```

The executor creates role work orders, can run configured external role commands, accepts role artifacts back into the task contract, and then continues through the same gates. It also runs the task decomposition gate before implementation.

## 5. Framework Doctor 2.0

`doctor-ai-sdlc.ps1` verifies required docs, configs, scripts, dashboard files, adapter templates, shell wrappers, PowerShell parsing, profile readiness, and writable evidence output.

## 6. AI Tool Adapter Layer

Adapters live under:

```text
adapters/
  codex/
  copilot/
  claude/
  cursor/
  generic/
```

They explain how each AI client should use the same task contract, handoff, reopen, approval, and evidence protocol.

## 7. Evidence Bundle As Main Output

`write-evidence-bundle.ps1` remains the final machine-readable handoff. It includes core pipeline reports plus framework reports, queue summaries, memory lifecycle status, reopen reports, doctor output, and approval records when present.

## 8. Memory Index Lifecycle

`check-memory-lifecycle.ps1` checks enabled memory providers from `context_memory.yaml`, source availability, index stamp freshness, and lifecycle warnings. Configuration lives in:

```text
tools/ai-sdlc/config/memory_lifecycle.yaml
```

## 9. Human Approval Gates

Approval records are written with `write-approval-record.ps1`. Required approval scopes are declared in task contracts and checked by `verify-approval-gate.ps1`.

If approval is missing, the dashboard receives a `waiting` event instead of pretending the task can continue.

## 10. CLI

Use one entrypoint where possible:

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 doctor -Pretty
```

macOS/Linux:

```sh
sh tools/ai-sdlc/scripts/ai-sdlc.sh doctor
```

Supported commands: `doctor`, `dashboard`, `new-task`, `decompose`, `queue`, `executor`, `submit-artifact`, `handoff`, `reopen-policy`, `approval`, `memory`, `evidence`, `pipeline`, and `orchestrator`.
