[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ImpactReportPath = "sdlc-impact-report.json",
    [string] $JsonOutputPath = "sdlc-validation-plan.json",
    [string] $MarkdownOutputPath = "sdlc-validation-plan.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$impactPath = if ([System.IO.Path]::IsPathRooted($ImpactReportPath)) { $ImpactReportPath } else { Join-Path $rootPath $ImpactReportPath }
$impact = Get-Content -LiteralPath $impactPath -Raw | ConvertFrom-Json

$commands = [System.Collections.Generic.List[object]]::new()
$index = 0
foreach ($command in @($impact.validationCommands)) {
    $index += 1
    $commands.Add([ordered]@{
        id = "validation_$index"
        command = $command
        required = $true
        reason = "Selected from project profile for changed areas: $(@($impact.changedAreas) -join ', ')"
    })
}

if ($commands.Count -eq 0) {
    $commands.Add([ordered]@{
        id = "validation_manual"
        command = "echo `"No validation command configured. Edit tools/ai-sdlc/config/project-profile.yaml.`""
        required = $false
        reason = "No profile validation commands were configured."
    })
}

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    impactReportPath = $impactPath
    changedAreas = @($impact.changedAreas)
    riskScore = $impact.riskScore
    complexity = $impact.complexity
    commands = @($commands)
}

$lines = @(
    "- Changed areas: $(@($impact.changedAreas) -join ', ')",
    "- Complexity: $($impact.complexity)",
    "- Risk score: $($impact.riskScore)",
    "- Command count: $($commands.Count)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $rootPath $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $rootPath $MarkdownOutputPath }

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Validation Plan" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}
