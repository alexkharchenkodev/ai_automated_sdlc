# Framework Doctor

`doctor-ai-sdlc` verifies that the portable AI SDLC framework is installed, configured, writable, and ready to produce useful evidence.

Use it after install, after framework updates, in CI bootstrap checks, and when the dashboard or pipeline has incomplete data.

## Windows

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\doctor-ai-sdlc.ps1 -Pretty
```

Fail on warnings too:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\doctor-ai-sdlc.ps1 -FailOnWarnings -Pretty
```

## macOS/Linux

```sh
sh ./tools/ai-sdlc/scripts/doctor-ai-sdlc.sh
```

Fail on warnings too:

```sh
sh ./tools/ai-sdlc/scripts/doctor-ai-sdlc.sh --fail-on-warnings
```

## Output

Reports are written under:

```text
.sdlc/doctor/
  sdlc-doctor-report.json
  sdlc-doctor-report.md
```

Decision values:

- `proceed`: framework is ready.
- `review_required`: framework can run, but configuration is incomplete or advisory pieces are missing.
- `blocked`: required files are missing, scripts do not parse, or `.sdlc` evidence output is not writable.

The live dashboard reads the doctor report when it exists and shows framework readiness.
