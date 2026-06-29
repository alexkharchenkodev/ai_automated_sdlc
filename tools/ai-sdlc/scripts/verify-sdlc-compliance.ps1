[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ReportDirectory = ".sdlc/local-pipeline",
    [string] $JsonOutputPath = "sdlc-compliance-report.json",
    [string] $MarkdownOutputPath = "sdlc-compliance-report.md",
    [switch] $AllowReviewRequired,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]] $List,
        [string] $Code,
        [string] $Message
    )
    $List.Add([ordered]@{ code = $Code; message = $Message })
}

function Read-ReportOrNull {
    param([string] $Path)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    return $null
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }

$blockers = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[object]]::new()

$lanePath = Join-Path $reportRoot "sdlc-lane-report.json"
$impactPath = Join-Path $reportRoot "sdlc-impact-report.json"
$validationPath = Join-Path $reportRoot "sdlc-selected-validation-report.json"
$safePath = Join-Path $reportRoot "sdlc-safe-change-report.json"
$tokenPath = Join-Path $reportRoot "sdlc-token-usage-report.json"
$bundlePath = Join-Path $reportRoot "sdlc-evidence-bundle.json"
$contextPath = Join-Path $reportRoot "sdlc-context-memory-report.json"
$integrationsPath = Join-Path $reportRoot "sdlc-integrations-report.json"

$lane = Read-ReportOrNull -Path $lanePath
$impact = Read-ReportOrNull -Path $impactPath
$validation = Read-ReportOrNull -Path $validationPath
$safeChange = Read-ReportOrNull -Path $safePath
$tokenUsage = Read-ReportOrNull -Path $tokenPath
$bundle = Read-ReportOrNull -Path $bundlePath
$contextMemory = Read-ReportOrNull -Path $contextPath
$integrations = Read-ReportOrNull -Path $integrationsPath

if (-not $lane) {
    Add-Finding -List $blockers -Code "lane_missing" -Message "Missing sdlc-lane-report.json. Run select-sdlc-lane.ps1 or the full pipeline."
}

$requiredReports = if ($lane) { @($lane.requiredReports) } else { @(
    "sdlc-impact-report.json",
    "sdlc-task-intake-report.json",
    "sdlc-validation-plan.json",
    "sdlc-selected-validation-report.json",
    "sdlc-safe-change-report.json",
    "sdlc-evidence-bundle.json"
) }

$reportStatuses = [System.Collections.Generic.List[object]]::new()
foreach ($report in $requiredReports) {
    $path = Join-Path $reportRoot $report
    $present = Test-Path -LiteralPath $path
    if (-not $present) {
        Add-Finding -List $blockers -Code "required_report_missing" -Message "Missing required report for selected lane: $report"
    }
    $reportStatuses.Add([ordered]@{
        path = $report
        present = $present
        sizeBytes = if ($present) { (Get-Item -LiteralPath $path).Length } else { 0 }
    })
}

if ($impact -and @($impact.changedFiles).Count -eq 0) {
    Add-Finding -List $warnings -Code "no_changed_files" -Message "No changed files were supplied; compliance can only verify framework plumbing."
}

if ($validation) {
    if (-not [bool]$validation.passed) {
        Add-Finding -List $blockers -Code "validation_failed" -Message "Selected validation did not pass."
    }
    if ([bool]$validation.skipped) {
        if ($lane -and [bool]$lane.requireValidationExecution) {
            Add-Finding -List $blockers -Code "validation_execution_required" -Message "Selected lane requires real validation execution; rerun without SkipValidationExecution."
        } else {
            Add-Finding -List $warnings -Code "validation_skipped" -Message "Validation execution was skipped; decision cannot be fully trusted."
        }
    }
} else {
    Add-Finding -List $blockers -Code "validation_report_missing" -Message "Missing selected validation report."
}

if ($safeChange) {
    if (-not [bool]$safeChange.passed) {
        Add-Finding -List $blockers -Code "safe_change_blocked" -Message "Safe-change gate did not pass."
    }
} else {
    Add-Finding -List $blockers -Code "safe_change_missing" -Message "Missing safe-change report."
}

if ($bundle) {
    if ($bundle.decision -eq "blocked") {
        Add-Finding -List $blockers -Code "evidence_bundle_blocked" -Message "Evidence bundle decision is blocked."
    } elseif ($bundle.decision -ne "proceed") {
        Add-Finding -List $warnings -Code "evidence_bundle_review" -Message "Evidence bundle requires review."
    }
} else {
    Add-Finding -List $blockers -Code "evidence_bundle_missing" -Message "Missing evidence bundle."
}

if ($tokenUsage) {
    if ($tokenUsage.decision -eq "blocked") {
        Add-Finding -List $blockers -Code "token_budget_blocked" -Message "Token budget decision is blocked."
    } elseif ($tokenUsage.decision -ne "proceed") {
        Add-Finding -List $warnings -Code "token_budget_review" -Message "Token budget requires review."
    }
}

if ($contextMemory -and -not [bool]$contextMemory.passed) {
    Add-Finding -List $warnings -Code "context_memory_incomplete" -Message "Context memory report is incomplete or requires configuration."
}

if ($integrations -and -not [bool]$integrations.passed) {
    Add-Finding -List $warnings -Code "integrations_incomplete" -Message "Integration readiness is incomplete or requires configuration."
}

$decision = if ($blockers.Count -gt 0) {
    "blocked"
} elseif ($warnings.Count -gt 0) {
    "review_required"
} else {
    "proceed"
}

$passed = if ($decision -eq "proceed") { $true } elseif ($decision -eq "review_required" -and $AllowReviewRequired) { $true } else { $false }

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    reportDirectory = $reportRoot
    passed = $passed
    decision = $decision
    allowReviewRequired = [bool]$AllowReviewRequired
    lane = if ($lane) { $lane.lane } else { "unknown" }
    laneTitle = if ($lane) { $lane.title } else { "Unknown" }
    riskScore = if ($impact) { $impact.riskScore } else { $null }
    validationSkipped = if ($validation) { [bool]$validation.skipped } else { $null }
    blockers = @($blockers)
    warnings = @($warnings)
    requiredReports = @($reportStatuses)
}

$lines = @(
    "- Passed: $passed",
    "- Decision: $decision",
    "- Lane: $($result.lane)",
    "- Risk score: $($result.riskScore)",
    "- Blockers: $($blockers.Count)",
    "- Warnings: $($warnings.Count)",
    "- Allow review-required: $([bool]$AllowReviewRequired)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $reportRoot $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $reportRoot $MarkdownOutputPath }
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Compliance Report" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}

if (-not $passed) {
    if ($decision -eq "review_required") { exit 2 }
    exit 1
}
