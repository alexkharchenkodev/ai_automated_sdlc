[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ReportDirectory = ".sdlc/local-pipeline",
    [string] $ApprovalDirectory = ".sdlc/approvals",
    [string] $JsonOutputPath = "sdlc-safe-change-report.json",
    [string] $MarkdownOutputPath = "sdlc-safe-change-report.md",
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

$rootPath = Resolve-AiSdlcRoot -Root $Root
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
$approvalRoot = if ([System.IO.Path]::IsPathRooted($ApprovalDirectory)) { $ApprovalDirectory } else { Join-Path $rootPath $ApprovalDirectory }

$blockers = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[object]]::new()

$impactPath = Join-Path $reportRoot "sdlc-impact-report.json"
$validationPath = Join-Path $reportRoot "sdlc-selected-validation-report.json"
$rollbackPath = Join-Path $reportRoot "sdlc-rollback-plan.json"

foreach ($required in @("sdlc-impact-report.json", "sdlc-task-intake-report.json", "sdlc-validation-plan.json", "sdlc-selected-validation-report.json", "sdlc-rollback-plan.json")) {
    if (-not (Test-Path -LiteralPath (Join-Path $reportRoot $required))) {
        Add-Finding -List $blockers -Code "missing_report" -Message "Missing required report: $required"
    }
}

$impact = if (Test-Path -LiteralPath $impactPath) { Get-Content -LiteralPath $impactPath -Raw | ConvertFrom-Json } else { $null }
$validation = if (Test-Path -LiteralPath $validationPath) { Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json } else { $null }
$rollback = if (Test-Path -LiteralPath $rollbackPath) { Get-Content -LiteralPath $rollbackPath -Raw | ConvertFrom-Json } else { $null }

if ($validation -and -not [bool]$validation.passed) {
    Add-Finding -List $blockers -Code "validation_failed" -Message "Selected validation did not pass."
}

if ($impact) {
    if ([int]$impact.riskScore -ge 3 -and -not $rollback) {
        Add-Finding -List $blockers -Code "rollback_missing" -Message "Risk score requires rollback plan."
    }

    $approvedScopes = [System.Collections.Generic.List[string]]::new()
    if (Test-Path -LiteralPath $approvalRoot) {
        Get-ChildItem -LiteralPath $approvalRoot -Filter "approval-*.json" -File | ForEach-Object {
            try {
                $approval = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
                if ($approval.status -eq "approved") {
                    $approvedScopes.Add([string]$approval.scope)
                }
            } catch {
                Add-Finding -List $warnings -Code "approval_read_failed" -Message "Could not read approval record: $($_.FullName)"
            }
        }
    }

    foreach ($requiredApproval in @($impact.requiredApprovals)) {
        if (-not ($approvedScopes.Contains([string]$requiredApproval) -or $approvedScopes.Contains("all"))) {
            Add-Finding -List $blockers -Code "approval_missing" -Message "Missing approval for scope: $requiredApproval"
        }
    }

    if (@($impact.changedFiles).Count -eq 0) {
        Add-Finding -List $warnings -Code "no_changed_files" -Message "No changed files were supplied; safety coverage is limited."
    }
}

$passed = ($blockers.Count -eq 0)
$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    reportDirectory = $reportRoot
    approvalDirectory = $approvalRoot
    passed = $passed
    decision = if ($passed) { "proceed" } else { "blocked" }
    blockers = @($blockers)
    warnings = @($warnings)
}

$lines = @(
    "- Passed: $passed",
    "- Decision: $($result.decision)",
    "- Blockers: $($blockers.Count)",
    "- Warnings: $($warnings.Count)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $reportRoot $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $reportRoot $MarkdownOutputPath }
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Safe Change Report" -Lines $lines

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
