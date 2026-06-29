[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ImpactReportPath = "sdlc-impact-report.json",
    [string] $JsonOutputPath = "sdlc-lane-report.json",
    [string] $MarkdownOutputPath = "sdlc-lane-report.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$resolvedImpactPath = if ([System.IO.Path]::IsPathRooted($ImpactReportPath)) { $ImpactReportPath } else { Join-Path $rootPath $ImpactReportPath }
$impact = Get-Content -LiteralPath $resolvedImpactPath -Raw | ConvertFrom-Json

$riskScore = [int]$impact.riskScore
$requiredApprovals = @($impact.requiredApprovals)
$riskSignals = @($impact.riskSignals)

$laneId = if ($riskScore -ge 7 -or $requiredApprovals.Count -gt 0 -or ($riskSignals -contains "touches_security_sensitive_file") -or ($riskSignals -contains "touches_ci")) {
    "strict"
} elseif ($riskScore -ge 3) {
    "standard"
} else {
    "fast"
}

$laneDefaults = @{
    fast = [ordered]@{
        title = "Fast Lane"
        purpose = "Small scoped changes with low blast radius."
        requireHumanApproval = $false
        requireValidationExecution = $false
        skippedValidationDecision = "review_required"
        requiredReports = @(
            "sdlc-impact-report.json",
            "sdlc-task-intake-report.json",
            "sdlc-validation-plan.json",
            "sdlc-selected-validation-report.json",
            "sdlc-safe-change-report.json",
            "sdlc-evidence-bundle.json"
        )
    }
    standard = [ordered]@{
        title = "Standard Lane"
        purpose = "Normal feature and bug-fix work where evidence should be complete."
        requireHumanApproval = $false
        requireValidationExecution = $false
        skippedValidationDecision = "review_required"
        requiredReports = @(
            "sdlc-impact-report.json",
            "sdlc-task-intake-report.json",
            "sdlc-context-memory-report.json",
            "sdlc-integrations-report.json",
            "sdlc-impacted-tests.json",
            "sdlc-rollback-plan.json",
            "sdlc-validation-plan.json",
            "sdlc-selected-validation-report.json",
            "sdlc-safe-change-report.json",
            "sdlc-token-usage-report.json",
            "sdlc-evidence-bundle.json"
        )
    }
    strict = [ordered]@{
        title = "Strict Lane"
        purpose = "High-risk, security-sensitive, schema/API, CI, dependency, or broad changes."
        requireHumanApproval = $true
        requireValidationExecution = $true
        skippedValidationDecision = "blocked"
        requiredReports = @(
            "sdlc-impact-report.json",
            "sdlc-task-intake-report.json",
            "sdlc-context-memory-report.json",
            "sdlc-integrations-report.json",
            "sdlc-impacted-tests.json",
            "sdlc-rollback-plan.json",
            "sdlc-validation-plan.json",
            "sdlc-selected-validation-report.json",
            "sdlc-safe-change-report.json",
            "sdlc-token-usage-report.json",
            "sdlc-evidence-bundle.json"
        )
    }
}

$lane = $laneDefaults[$laneId]
$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    impactReportPath = $resolvedImpactPath
    lane = $laneId
    title = $lane.title
    purpose = $lane.purpose
    decision = "selected"
    riskScore = $riskScore
    complexity = $impact.complexity
    reviewTier = $impact.reviewTier
    requireHumanApproval = [bool]$lane.requireHumanApproval
    requireValidationExecution = [bool]$lane.requireValidationExecution
    skippedValidationDecision = $lane.skippedValidationDecision
    requiredReports = @($lane.requiredReports)
    requiredApprovals = @($requiredApprovals)
    riskSignals = @($riskSignals)
}

$lines = @(
    "- Lane: $($result.lane) ($($result.title))",
    "- Purpose: $($result.purpose)",
    "- Risk score: $riskScore",
    "- Complexity: $($impact.complexity)",
    "- Review tier: $($impact.reviewTier)",
    "- Requires human approval: $($result.requireHumanApproval)",
    "- Requires validation execution: $($result.requireValidationExecution)",
    "- Required reports: $(@($result.requiredReports).Count)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $rootPath $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $rootPath $MarkdownOutputPath }
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Execution Lane Report" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}
