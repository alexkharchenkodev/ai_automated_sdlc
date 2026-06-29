[CmdletBinding()]
param(
    [string] $Root = "."
)

$ErrorActionPreference = "Stop"
$rootPath = if (Test-Path -LiteralPath $Root) { (Resolve-Path -LiteralPath $Root).Path } else { throw "Root not found: $Root" }

$required = @(
    "AGENTS.md",
    "docs/SDLC/README.md",
    "docs/SDLC/ai_sdlc_overview.md",
    "docs/SDLC/agent_failure_mode_gates.md",
    "docs/LLM/llm_code_generation_do_dont.md",
    "docs/LLM/canonical_naming_rules.md",
    "tools/ai-sdlc/config/project-profile.yaml",
    "tools/ai-sdlc/config/portable_gates.yaml",
    "tools/ai-sdlc/config/context_memory.yaml",
    "tools/ai-sdlc/config/memory_lifecycle.yaml",
    "tools/ai-sdlc/config/integrations.yaml",
    "tools/ai-sdlc/config/token_budget.yaml",
    "tools/ai-sdlc/config/execution_lanes.yaml",
    "tools/ai-sdlc/config/handoff_gates.yaml",
    "tools/ai-sdlc/config/reopen_policy.yaml",
    "tools/ai-sdlc/config/approval_gates.yaml",
    "tools/ai-sdlc/config/mcp_servers.example.yaml",
    "tools/ai-sdlc/scripts/ai-sdlc.ps1",
    "tools/ai-sdlc/scripts/ai-sdlc.sh",
    "tools/ai-sdlc/scripts/new-task-contract.ps1",
    "tools/ai-sdlc/scripts/run-ai-sdlc-task-queue.ps1",
    "tools/ai-sdlc/scripts/verify-handoff-gate.ps1",
    "tools/ai-sdlc/scripts/verify-reopen-policy.ps1",
    "tools/ai-sdlc/scripts/verify-approval-gate.ps1",
    "tools/ai-sdlc/scripts/check-memory-lifecycle.ps1",
    "tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.ps1",
    "tools/ai-sdlc/scripts/analyze-impact.ps1",
    "tools/ai-sdlc/scripts/write-context-memory-report.ps1",
    "tools/ai-sdlc/scripts/check-integrations.ps1",
    "tools/ai-sdlc/scripts/estimate-token-usage.ps1",
    "tools/ai-sdlc/scripts/select-validation.ps1",
    "tools/ai-sdlc/scripts/select-sdlc-lane.ps1",
    "tools/ai-sdlc/scripts/write-evidence-bundle.ps1",
    "tools/ai-sdlc/scripts/validate-safe-change.ps1",
    "tools/ai-sdlc/scripts/verify-sdlc-compliance.ps1",
    "tools/ai-sdlc/scripts/verify-sdlc-compliance.sh",
    "tools/ai-sdlc/scripts/doctor-ai-sdlc.ps1",
    "tools/ai-sdlc/scripts/doctor-ai-sdlc.sh",
    "tools/ai-sdlc/scripts/write-rollback-plan.ps1",
    "tools/ai-sdlc/scripts/select-impacted-tests.ps1",
    "tools/ai-sdlc/scripts/write-approval-record.ps1",
    "tools/ai-sdlc/scripts/write-role-event.ps1",
    "tools/ai-sdlc/scripts/start-ai-sdlc-dashboard.ps1",
    "tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.ps1",
    "tools/ai-sdlc/config/role_flow.yaml",
    "tools/ai-sdlc/config/safety_gates.yaml",
    "dashboard/index.html",
    "dashboard/styles.css",
    "dashboard/app.js",
    "adapters/codex/AGENTS.md",
    "adapters/copilot/copilot-instructions.md",
    "adapters/claude/CLAUDE.md",
    "adapters/cursor/rules.md",
    "adapters/generic/ai-agent-adapter.md",
    ".github/workflows/ai-sdlc.yml",
    ".github/PULL_REQUEST_TEMPLATE.md"
)

$missing = @()
foreach ($relative in $required) {
    $path = Join-Path $rootPath $relative
    if (-not (Test-Path -LiteralPath $path)) {
        $missing += $relative
    }
}

$result = [ordered]@{
    root = $rootPath
    passed = ($missing.Count -eq 0)
    missing = $missing
}

$result | ConvertTo-Json -Depth 5

if ($missing.Count -gt 0) {
    exit 1
}
