# Pull Request

## Summary

- 

## AI SDLC

- [ ] Primary target is explicit.
- [ ] Acceptance criteria are clear.
- [ ] Protected surfaces were respected.
- [ ] Automated local SDLC pipeline was run or intentionally skipped.

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\ai-sdlc\scripts\run-ai-sdlc-pipeline.ps1 -ChangedFilesPath changed-files.txt -Pretty
```

## Validation

- [ ] Build/test commands from `tools/ai-sdlc/config/project-profile.yaml` passed, or skip reason is documented.
- [ ] Evidence bundle is attached or available in `.sdlc/local-pipeline/`.

## Risk

- Human approval required: yes/no
- Schema/API contract impact: yes/no
- Security-sensitive impact: yes/no
- Release impact: yes/no

## Notes

- 
