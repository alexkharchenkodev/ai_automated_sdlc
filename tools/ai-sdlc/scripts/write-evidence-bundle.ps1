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
    "sdlc-lane-report.json",
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
$frameworkReports = [System.Collections.Generic.List[object]]::new()
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

$optionalFrameworkReports = @(
    "sdlc-task-queue-summary.json",
    "sdlc-executor-summary.json",
    "sdlc-memory-lifecycle-report.json",
    "sdlc-reopen-policy-all-tasks.json",
    "sdlc-doctor-report.json"
)
foreach ($report in $optionalFrameworkReports) {
    $matches = @(Get-ChildItem -LiteralPath $reportRoot -Recurse -Filter $report -File -ErrorAction SilentlyContinue)
    $frameworkReports.Add([ordered]@{
        path = $report
        present = ($matches.Count -gt 0)
        matches = @($matches | ForEach-Object { $_.FullName })
    })
}

$approvalRecords = @()
$approvalRoot = Join-Path $rootPath ".sdlc/approvals"
if (Test-Path -LiteralPath $approvalRoot) {
    $approvalRecords = @(Get-ChildItem -LiteralPath $approvalRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [ordered]@{
            path = $_.FullName
            sizeBytes = $_.Length
        }
    })
}

$validationPath = Join-Path $reportRoot "sdlc-selected-validation-report.json"
$lanePath = Join-Path $reportRoot "sdlc-lane-report.json"
$safeChangePath = Join-Path $reportRoot "sdlc-safe-change-report.json"
$contextPath = Join-Path $reportRoot "sdlc-context-memory-report.json"
$integrationsPath = Join-Path $reportRoot "sdlc-integrations-report.json"
$tokenPath = Join-Path $reportRoot "sdlc-token-usage-report.json"
$validationPassed = $false
$validationSkipped = $null
if (Test-Path -LiteralPath $validationPath) {
    $validation = Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json
    $validationPassed = [bool]$validation.passed
    $validationSkipped = [bool]$validation.skipped
}
$laneName = "unknown"
$laneRequiresValidation = $false
if (Test-Path -LiteralPath $lanePath) {
    $lane = Get-Content -LiteralPath $lanePath -Raw | ConvertFrom-Json
    $laneName = $lane.lane
    $laneRequiresValidation = [bool]$lane.requireValidationExecution
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

$laneValidationSatisfied = -not ($laneRequiresValidation -and [bool]$validationSkipped)
$passed = ($missing.Count -eq 0 -and $validationPassed -and $laneValidationSatisfied -and $safeChangePassed -and $contextPassed -and $integrationsPassed -and $tokenPassed)
$decision = if ($passed) {
    "proceed"
} elseif (-not $safeChangePassed -or -not $laneValidationSatisfied -or $tokenDecision -eq "blocked") {
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
    lane = $laneName
    laneRequiresValidationExecution = $laneRequiresValidation
    validationSkipped = $validationSkipped
    validationPassed = $validationPassed
    safeChangePassed = $safeChangePassed
    contextMemoryPassed = $contextPassed
    integrationsPassed = $integrationsPassed
    tokenUsagePassed = $tokenPassed
    tokenUsageDecision = $tokenDecision
    missingReports = @($missing)
    reports = @($reports)
    frameworkReports = @($frameworkReports)
    approvalRecords = @($approvalRecords)
}

$lines = @(
    "- Passed: $passed",
    "- Decision: $($result.decision)",
    "- Lane: $laneName",
    "- Validation passed: $validationPassed",
    "- Validation skipped: $validationSkipped",
    "- Context memory passed: $contextPassed",
    "- Integrations passed: $integrationsPassed",
    "- Token usage passed: $tokenPassed",
    "- Missing reports: $($missing.Count)",
    "- Framework reports present: $(@($frameworkReports | Where-Object { $_.present }).Count)/$($frameworkReports.Count)",
    "- Approval records: $($approvalRecords.Count)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $reportRoot $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $reportRoot $MarkdownOutputPath }

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Evidence Bundle" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}
