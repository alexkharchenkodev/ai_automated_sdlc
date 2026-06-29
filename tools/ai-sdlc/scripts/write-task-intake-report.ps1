[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $Task = "",
    [string] $ImpactReportPath = "sdlc-impact-report.json",
    [string] $JsonOutputPath = "sdlc-task-intake-report.json",
    [string] $MarkdownOutputPath = "sdlc-task-intake-report.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$impactPath = if ([System.IO.Path]::IsPathRooted($ImpactReportPath)) { $ImpactReportPath } else { Join-Path $rootPath $ImpactReportPath }
$impact = Get-Content -LiteralPath $impactPath -Raw | ConvertFrom-Json
$summary = if ($Task) { $Task } else { "AI SDLC work item for changed areas: $(@($impact.changedAreas) -join ', ')." }

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    ready = ($impact.changedFiles.Count -gt 0)
    task = [ordered]@{
        title = $summary
        type = "local_change"
        area = @($impact.changedAreas)
        primaryTarget = if ($impact.changedFiles.Count -gt 0) { $impact.changedFiles[0] } else { "" }
        acceptanceCriteria = @(
            "Change is scoped to the requested target.",
            "Required validation plan is run or explicitly skipped with reason.",
            "Evidence bundle is generated."
        )
    }
    impact = $impact
}

$lines = @(
    "- Ready: $($result.ready)",
    "- Title: $summary",
    "- Area: $(@($impact.changedAreas) -join ', ')",
    "- Primary target: $($result.task.primaryTarget)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $rootPath $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $rootPath $MarkdownOutputPath }

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Task Intake Report" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}
