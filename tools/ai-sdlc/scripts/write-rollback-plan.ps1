[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ImpactReportPath = "sdlc-impact-report.json",
    [string] $JsonOutputPath = "sdlc-rollback-plan.json",
    [string] $MarkdownOutputPath = "sdlc-rollback-plan.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$impactPath = if ([System.IO.Path]::IsPathRooted($ImpactReportPath)) { $ImpactReportPath } else { Join-Path $rootPath $ImpactReportPath }
$impact = Get-Content -LiteralPath $impactPath -Raw | ConvertFrom-Json

$steps = [System.Collections.Generic.List[string]]::new()
$steps.Add("Stop and capture current failing behavior or deployment state.")
$steps.Add("Revert or restore changed files listed in the impact report if the change is code-only.")

if (@($impact.changedAreas) -contains "contract" -or @($impact.riskSignals) -contains "touches_schema_or_api_contract") {
    $steps.Add("Check API/schema consumers before rollback; restore compatible contract files first.")
}

if (@($impact.changedAreas) -contains "security") {
    $steps.Add("Rotate exposed credentials if any secret-like file was modified or leaked.")
}

if (@($impact.changedAreas) -contains "dependencies") {
    $steps.Add("Restore lockfile and package manifest together; reinstall dependencies from the restored lockfile.")
}

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    impactReportPath = $impactPath
    riskScore = $impact.riskScore
    changedFiles = @($impact.changedFiles)
    changedAreas = @($impact.changedAreas)
    rollbackRequired = ([int]$impact.riskScore -ge 3)
    steps = @($steps)
}

$lines = @(
    "- Risk score: $($impact.riskScore)",
    "- Rollback required: $($result.rollbackRequired)",
    "- Changed files: $(@($impact.changedFiles).Count)",
    "",
    "## Steps"
) + (@($steps) | ForEach-Object { "- $_" })

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $rootPath $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $rootPath $MarkdownOutputPath }
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Rollback Plan" -Lines $lines

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
