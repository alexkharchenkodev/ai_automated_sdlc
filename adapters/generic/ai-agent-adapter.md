# Generic AI Agent Adapter

This file describes the minimal contract for any AI coding client.

## Agent Responsibilities

1. Read project-local rules.
2. Run AI SDLC doctor.
3. Create or update a task contract.
4. Emit role events for dashboard visibility.
5. Verify handoff, reopen, approval, memory, validation, and evidence gates.
6. Produce an evidence bundle as the main machine-readable output.

## Portable CLI

Windows:

```powershell
powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/ai-sdlc.ps1 doctor -Pretty
```

macOS/Linux:

```sh
sh tools/ai-sdlc/scripts/ai-sdlc.sh doctor
```

