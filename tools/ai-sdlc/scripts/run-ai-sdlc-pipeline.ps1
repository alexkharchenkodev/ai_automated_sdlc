[CmdletBinding()]
param(
    [string] $Root = ".",
    [string[]] $ChangedFile = @(),
    [string] $ChangedFilesPath = "",
    [string] $Task = "",
    [string] $ReportDirectory = ".sdlc/local-pipeline",
    [switch] $SkipValidationExecution,
    [switch] $Pretty
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) {
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
}

$impactJson = Join-Path $reportRoot "sdlc-impact-report.json"
$impactMd = Join-Path $reportRoot "sdlc-impact-report.md"
$taskJson = Join-Path $reportRoot "sdlc-task-intake-report.json"
$taskMd = Join-Path $reportRoot "sdlc-task-intake-report.md"
$contextJson = Join-Path $reportRoot "sdlc-context-memory-report.json"
$contextMd = Join-Path $reportRoot "sdlc-context-memory-report.md"
$integrationsJson = Join-Path $reportRoot "sdlc-integrations-report.json"
$integrationsMd = Join-Path $reportRoot "sdlc-integrations-report.md"
$impactedTestsJson = Join-Path $reportRoot "sdlc-impacted-tests.json"
$impactedTestsMd = Join-Path $reportRoot "sdlc-impacted-tests.md"
$rollbackJson = Join-Path $reportRoot "sdlc-rollback-plan.json"
$rollbackMd = Join-Path $reportRoot "sdlc-rollback-plan.md"
$planJson = Join-Path $reportRoot "sdlc-validation-plan.json"
$planMd = Join-Path $reportRoot "sdlc-validation-plan.md"
$validationJson = Join-Path $reportRoot "sdlc-selected-validation-report.json"
$validationMd = Join-Path $reportRoot "sdlc-selected-validation-report.md"
$safeJson = Join-Path $reportRoot "sdlc-safe-change-report.json"
$safeMd = Join-Path $reportRoot "sdlc-safe-change-report.md"
$tokenJson = Join-Path $reportRoot "sdlc-token-usage-report.json"
$tokenMd = Join-Path $reportRoot "sdlc-token-usage-report.md"
$bundleJson = Join-Path $reportRoot "sdlc-evidence-bundle.json"
$bundleMd = Join-Path $reportRoot "sdlc-evidence-bundle.md"

& "$PSScriptRoot/analyze-impact.ps1" -Root $rootPath -ChangedFile $ChangedFile -ChangedFilesPath $ChangedFilesPath -JsonOutputPath $impactJson -MarkdownOutputPath $impactMd | Out-Null
& "$PSScriptRoot/write-task-intake-report.ps1" -Root $rootPath -Task $Task -ImpactReportPath $impactJson -JsonOutputPath $taskJson -MarkdownOutputPath $taskMd | Out-Null
& "$PSScriptRoot/write-context-memory-report.ps1" -Root $rootPath -JsonOutputPath $contextJson -MarkdownOutputPath $contextMd | Out-Null
& "$PSScriptRoot/check-integrations.ps1" -Root $rootPath -JsonOutputPath $integrationsJson -MarkdownOutputPath $integrationsMd | Out-Null
& "$PSScriptRoot/select-impacted-tests.ps1" -Root $rootPath -ImpactReportPath $impactJson -JsonOutputPath $impactedTestsJson -MarkdownOutputPath $impactedTestsMd | Out-Null
& "$PSScriptRoot/write-rollback-plan.ps1" -Root $rootPath -ImpactReportPath $impactJson -JsonOutputPath $rollbackJson -MarkdownOutputPath $rollbackMd | Out-Null
& "$PSScriptRoot/select-validation.ps1" -Root $rootPath -ImpactReportPath $impactJson -JsonOutputPath $planJson -MarkdownOutputPath $planMd | Out-Null
& "$PSScriptRoot/run-validation-plan.ps1" -Root $rootPath -PlanPath $planJson -JsonOutputPath $validationJson -MarkdownOutputPath $validationMd -SkipExecution:$SkipValidationExecution | Out-Null
& "$PSScriptRoot/validate-safe-change.ps1" -Root $rootPath -ReportDirectory $reportRoot -JsonOutputPath $safeJson -MarkdownOutputPath $safeMd | Out-Null
& "$PSScriptRoot/estimate-token-usage.ps1" -Root $rootPath -ImpactReportPath $impactJson -ReportDirectory $reportRoot -JsonOutputPath $tokenJson -MarkdownOutputPath $tokenMd | Out-Null
& "$PSScriptRoot/write-evidence-bundle.ps1" -Root $rootPath -ReportDirectory $reportRoot -JsonOutputPath $bundleJson -MarkdownOutputPath $bundleMd | Out-Null

$impact = Get-Content -LiteralPath $impactJson -Raw | ConvertFrom-Json
$validation = Get-Content -LiteralPath $validationJson -Raw | ConvertFrom-Json
$safeChange = Get-Content -LiteralPath $safeJson -Raw | ConvertFrom-Json
$contextMemory = Get-Content -LiteralPath $contextJson -Raw | ConvertFrom-Json
$integrations = Get-Content -LiteralPath $integrationsJson -Raw | ConvertFrom-Json
$tokenUsage = Get-Content -LiteralPath $tokenJson -Raw | ConvertFrom-Json
$bundle = Get-Content -LiteralPath $bundleJson -Raw | ConvertFrom-Json

$summary = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    passed = [bool]$bundle.passed
    reportDirectory = $reportRoot
    changedAreas = @($impact.changedAreas)
    complexity = $impact.complexity
    riskScore = $impact.riskScore
    requiresHumanApproval = [bool]$impact.requiresHumanApproval
    validationPassed = [bool]$validation.passed
    safeChangePassed = [bool]$safeChange.passed
    safeChangeDecision = $safeChange.decision
    contextMemoryDecision = $contextMemory.decision
    integrationsDecision = $integrations.decision
    tokenUsageDecision = $tokenUsage.decision
    estimatedTokens = $tokenUsage.estimatedTokens
    evidenceDecision = $bundle.decision
    reports = [ordered]@{
        impact = $impactJson
        taskIntake = $taskJson
        contextMemory = $contextJson
        integrations = $integrationsJson
        impactedTests = $impactedTestsJson
        rollbackPlan = $rollbackJson
        validationPlan = $planJson
        selectedValidation = $validationJson
        safeChange = $safeJson
        tokenUsage = $tokenJson
        evidenceBundle = $bundleJson
    }
}

$summaryPath = Join-Path $reportRoot "sdlc-summary.json"
$summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath

if ($Pretty) {
    $summary | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $summaryPath -Raw
}
