[CmdletBinding()]
param(
    [string] $Root = ".",
    [string[]] $ChangedFile = @(),
    [string] $ChangedFilesPath = "",
    [string] $ConfigPath = "",
    [string] $JsonOutputPath = "sdlc-impact-report.json",
    [string] $MarkdownOutputPath = "sdlc-impact-report.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Add-UniqueValue {
    param(
        [System.Collections.Generic.List[string]] $List,
        [string] $Value
    )
    if ($Value -and -not $List.Contains($Value)) {
        $List.Add($Value)
    }
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$profile = Read-AiSdlcProfile -Root $rootPath -ConfigPath $ConfigPath

$files = [System.Collections.Generic.List[string]]::new()
foreach ($file in $ChangedFile) {
    Add-UniqueValue -List $files -Value (ConvertTo-SdlcPath -Path $file)
}

if ($ChangedFilesPath) {
    foreach ($line in Get-Content -LiteralPath $ChangedFilesPath) {
        $trimmed = $line.Trim()
        if ($trimmed) {
            Add-UniqueValue -List $files -Value (ConvertTo-SdlcPath -Path $trimmed)
        }
    }
}

$areas = [System.Collections.Generic.List[string]]::new()
$riskSignals = [System.Collections.Generic.List[string]]::new()
$requiredApprovals = [System.Collections.Generic.List[string]]::new()
$riskScore = 0

foreach ($file in $files) {
    $matchedArea = $false

    foreach ($areaName in $profile.architectureAreas.Keys) {
        foreach ($areaPath in $profile.architectureAreas[$areaName]) {
            $path = (ConvertTo-SdlcPath -Path $areaPath).TrimEnd("/")
            if ($path -and ($file -eq $path -or $file.StartsWith("$path/"))) {
                Add-UniqueValue -List $areas -Value $areaName
                $matchedArea = $true
            }
        }
    }

    if ($file -match "^docs/SDLC/" -or $file -match "^tools/ai-sdlc/") {
        Add-UniqueValue -List $areas -Value "sdlc"
        Add-UniqueValue -List $riskSignals -Value "touches_sdlc_automation"
        $riskScore += 2
        $matchedArea = $true
    }

    if ($file -match "^\.github/workflows/" -or $file -match "^\.gitlab-ci" -or $file -match "azure-pipelines|circleci|buildkite") {
        Add-UniqueValue -List $areas -Value "ci"
        Add-UniqueValue -List $riskSignals -Value "touches_ci"
        $riskScore += 3
        $matchedArea = $true
    }

    if ($file -match "(schema|contract|openapi|swagger|migration|database|db/|api/|routes/)") {
        Add-UniqueValue -List $areas -Value "contract"
        Add-UniqueValue -List $riskSignals -Value "touches_schema_or_api_contract"
        Add-UniqueValue -List $requiredApprovals -Value "schema_or_api_contract_change"
        $riskScore += 4
    }

    if ($file -match "(^|/)(\.env|.*secret.*|.*credential.*|.*key.*|.*token.*|.*pem|.*p12)$") {
        Add-UniqueValue -List $areas -Value "security"
        Add-UniqueValue -List $riskSignals -Value "touches_security_sensitive_file"
        Add-UniqueValue -List $requiredApprovals -Value "security_sensitive_change"
        $riskScore += 6
    }

    if ($file -match "(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Gemfile\.lock|Podfile\.lock|gradle\.lockfile|packages\.lock\.json)") {
        Add-UniqueValue -List $areas -Value "dependencies"
        Add-UniqueValue -List $riskSignals -Value "touches_dependency_lockfile"
        $riskScore += 2
    }

    if (-not $matchedArea) {
        Add-UniqueValue -List $areas -Value "other"
    }

    $riskScore += 1
}

if ($files.Count -eq 0) {
    Add-UniqueValue -List $areas -Value "none"
    Add-UniqueValue -List $riskSignals -Value "no_changed_files_supplied"
}

if ($files.Count -gt 10) {
    Add-UniqueValue -List $riskSignals -Value "large_change_set"
    $riskScore += 3
}

$riskScore = [Math]::Min($riskScore, 10)
$complexity = if ($riskScore -ge 7) { "high" } elseif ($riskScore -ge 3) { "medium" } else { "low" }
$reviewTier = if ($riskScore -ge 7) { "strict" } elseif ($riskScore -ge 3) { "standard" } else { "lightweight" }

if ($riskScore -ge 7) {
    Add-UniqueValue -List $requiredApprovals -Value "high_risk_change"
}

$validationCommands = [System.Collections.Generic.List[string]]::new()
if ($profile.buildCommands.Count -gt 0 -and $complexity -ne "low") {
    foreach ($command in $profile.buildCommands) { Add-UniqueValue -List $validationCommands -Value $command }
}
if ($profile.testCommands.Count -gt 0 -and $files.Count -gt 0) {
    foreach ($command in $profile.testCommands) { Add-UniqueValue -List $validationCommands -Value $command }
}
if ($profile.lintCommands.Count -gt 0 -and ($areas.Contains("ui") -or $areas.Contains("application") -or $areas.Contains("app"))) {
    foreach ($command in $profile.lintCommands) { Add-UniqueValue -List $validationCommands -Value $command }
}

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    project = [ordered]@{
        name = $profile.projectName
        profile = $profile.profileName
        stack = $profile.primaryStack
        profilePath = $profile.path
    }
    changedFiles = @($files)
    changedAreas = @($areas)
    complexity = $complexity
    riskScore = $riskScore
    riskSignals = @($riskSignals)
    reviewTier = $reviewTier
    requiredApprovals = @($requiredApprovals)
    requiresHumanApproval = ($requiredApprovals.Count -gt 0)
    validationCommands = @($validationCommands)
}

$lines = @(
    "- Project: $($profile.projectName) ($($profile.profileName))",
    "- Changed files: $($files.Count)",
    "- Changed areas: $(@($areas) -join ', ')",
    "- Complexity: $complexity",
    "- Risk score: $riskScore",
    "- Review tier: $reviewTier",
    "- Human approval required: $($requiredApprovals.Count -gt 0)",
    "- Validation commands: $($validationCommands.Count)"
)

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $JsonOutputPath -MarkdownPath $MarkdownOutputPath -Title "AI SDLC Impact Report" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $JsonOutputPath -Raw
}
