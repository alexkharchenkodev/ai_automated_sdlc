# Real Executor

The real executor is the portable bridge between AI SDLC contracts and any AI client or local automation process.

It does not hard-code Codex, Claude, Copilot, Cursor, Jira, or any vendor. Instead it uses three stable concepts:

- Task contracts in `.sdlc/task-contracts/`
- Role work orders in `.sdlc/executor/work-orders/`
- Role artifact submission through `submit-role-artifact.ps1`

## Modes

Before any role execution, the executor verifies task decomposition. If a task looks like a whole app, multi-screen workflow, or broad feature set, BA must decompose it into child task contracts. The executor will wait instead of allowing one large implementation pass.

`work_order`

Creates role work orders and marks the task as waiting. Use this when a human, Codex session, Copilot chat, Claude session, or external worker will read the work order and submit artifacts later.

`external`

Runs configured role commands from:

```text
tools/ai-sdlc/config/role_executors.yaml
```

Each command receives token-expanded paths such as `{{task_contract}}`, `{{role}}`, and `{{work_order}}`.

`simulate`

Fills minimal role outputs for smoke testing. Do not use this as proof that product code was implemented.

## Run Executor

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 executor -Mode work_order -Pretty
```

macOS/Linux:

```sh
sh tools/ai-sdlc/scripts/ai-sdlc.sh executor -Mode work_order
```

## Submit Role Artifacts

Any AI client can complete a role by updating the task contract:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 submit-artifact `
  -TaskContractPath ".sdlc/task-contracts/example.json" `
  -Role engineering `
  -Append "implementationNotes=Added checkout button handler.;changedFiles=src/checkout.ts"
```

After submission, rerun the executor. It reloads the contract, verifies required outputs, and continues through the next handoff gate.

## External Command Contract

An external role command should:

1. Read the work order JSON.
2. Read the task contract.
3. Do the role work.
4. Call `submit-role-artifact.ps1` or write the expected fields into the task contract.
5. Exit `0` only when the role outputs are complete.

If the command exits non-zero, the executor marks the role as failed and blocks the task.
