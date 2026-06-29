[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ReportDirectory = ".",
    [string] $JsonOutputPath = "sdlc-evidence-bundle.json",
    [string] $MarkdownOutputPath = "sdlc-evidence-bundle.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }

$requiredReports = @(
    "sdlc-impact-report.json",
    "sdlc-task-intake-report.json",
    "sdlc-context-memory-report.json",
    "sdlc-integrations-report.json",
    "sdlc-validation-plan.json",
    "sdlc-selected-validation-report.json",
    "sdlc-rollback-plan.json",
    "sdlc-safe-change-report.json",
    "sdlc-token-usage-report.json"
)

$reports = [System.Collections.Generic.List[object]]::new()
$missing = [System.Collections.Generic.List[string]]::new()

foreach ($report in $requiredReports) {
    $path = Join-Path $reportRoot $report
    $present = Test-Path -LiteralPath $path
    if (-not $present) {
        $missing.Add($report)
    }
    $reports.Add([ordered]@{
        path = $report
        present = $present
        sizeBytes = if ($present) { (Get-Item -LiteralPath $path).Length } else { 0 }
    })
}

$validationPath = Join-Path $reportRoot "sdlc-selected-validation-report.json"
$safeChangePath = Join-Path $reportRoot "sdlc-safe-change-report.json"
$contextPath = Join-Path $reportRoot "sdlc-context-memory-report.json"
$integrationsPath = Join-Path $reportRoot "sdlc-integrations-report.json"
$tokenPath = Join-Path $reportRoot "sdlc-token-usage-report.json"
$validationPassed = $false
if (Test-Path -LiteralPath $validationPath) {
    $validation = Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
    $validationPassed = [bool]$validation.passed
}
$safeChangePassed = $false
if (Test-Path -LiteralPath $safeChangePath) {
    $safeChange = Get-Content -LiteralPath $safeChangePath -Raw | ConvertFrom-Json
    $safeChangePassed = [bool]$safeChange.passed
}
$contextPassed = $false
if (Test-Path -LiteralPath $contextPath) {
    $contextMemory = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json
    $contextPassed = [bool]$contextMemory.passed
}
$integrationsPassed = $false
if (Test-Path -LiteralPath $integrationsPath) {
    $integrations = Get-Content -LiteralPath $integrationsPath -Raw | ConvertFrom-Json
    $integrationsPassed = [bool]$integrations.passed
}
$tokenPassed = $false
$tokenDecision = "missing"
if (Test-Path -LiteralPath $tokenPath) {
    $tokenUsage = Get-Content -LiteralPath $tokenPath -Raw | ConvertFrom-Json
    $tokenPassed = [bool]$tokenUsage.passed
    $tokenDecision = $tokenUsage.decision
}

$passed = ($missing.Count -eq 0 -and $validationPassed -and $safeChangePassed -and $contextPassed -and $integrationsPassed -and $tokenPassed)
$decision = if ($passed) {
    "proceed"
} elseif (-not $safeChangePassed -or $tokenDecision -eq "blocked") {
    "blocked"
} else {
    "review_required"
}

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    reportDirectory = $reportRoot
    passed = $passed
    decision = $decision
    validationPassed = $validationPassed
    safeChangePassed = $safeChangePassed
    contextMemoryPassed = $contextPassed
    integrationsPassed = $integrationsPassed
    tokenUsagePassed = $tokenPassed
    tokenUsageDecision = $tokenDecision
    missingReports = @($missing)
    reports = @($reports)
}

$lines = @(
    "- Passed: $passed",
    "- Decision: $($result.decision)",
    "- Validation passed: $validationPassed",
    "- Context memory passed: $contextPassed",
    "- Integrations passed: $integrationsPassed",
    "- Token usage passed: $tokenPassed",
    "- Missing reports: $($missing.Count)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $reportRoot $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $reportRoot $MarkdownOutputPath }

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Evidence Bundle" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}
