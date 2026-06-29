[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ContextReportPath = "",
    [string] $ConfigPath = "",
    [string] $ReportDirectory = ".sdlc/memory-lifecycle",
    [switch] $TouchIndex,
    [switch] $NoExitCode,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/memory_lifecycle.yaml" }
if (-not (Test-Path -LiteralPath $config)) { throw "Memory lifecycle config not found: $config" }
$settings = Get-YamlSectionScalarMap -Lines ((Get-Content -LiteralPath $config -Raw) -split "`r?`n") -RootKey "settings"
$maxAgeDays = if ($settings.max_index_age_days) { [int]$settings.max_index_age_days } else { 14 }
$stampDir = if ($settings.index_stamp_directory) { [string]$settings.index_stamp_directory } else { ".sdlc/memory-index" }
$stampRoot = if ([System.IO.Path]::IsPathRooted($stampDir)) { $stampDir } else { Join-Path $rootPath $stampDir }
if (-not (Test-Path -LiteralPath $stampRoot)) { New-Item -ItemType Directory -Force -Path $stampRoot | Out-Null }

$contextPath = if ($ContextReportPath) { if ([System.IO.Path]::IsPathRooted($ContextReportPath)) { $ContextReportPath } else { Join-Path $rootPath $ContextReportPath } } else { Join-Path $rootPath ".sdlc/local-pipeline/sdlc-context-memory-report.json" }
if (-not (Test-Path -LiteralPath $contextPath)) {
    $contextPath = Join-Path $rootPath ".sdlc/memory-lifecycle/sdlc-context-memory-report.json"
    & "$PSScriptRoot/write-context-memory-report.ps1" -Root $rootPath -JsonOutputPath $contextPath -MarkdownOutputPath ([System.IO.Path]::ChangeExtension($contextPath, ".md")) | Out-Null
}
$context = Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json

$now = (Get-Date).ToUniversalTime()
$providerReports = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
foreach ($provider in @($context.providers)) {
    $stampPath = Join-Path $stampRoot "$($provider.name).stamp.json"
    if ($TouchIndex -and $provider.enabled) {
        [ordered]@{
            schemaVersion = 1
            provider = $provider.name
            touchedAtUtc = $now.ToString("o")
            sourceCount = $provider.availableSources
        } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stampPath
    }

    $stampAgeDays = $null
    $stampStatus = "missing"
    if (Test-Path -LiteralPath $stampPath) {
        $stamp = Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json
        $stampTime = [datetime]$stamp.touchedAtUtc
        $stampAgeDays = [math]::Round(($now - $stampTime.ToUniversalTime()).TotalDays, 2)
        $stampStatus = if ($stampAgeDays -le $maxAgeDays) { "fresh" } else { "stale" }
    }

    if ($provider.enabled -and $provider.availableSources -eq 0) {
        $warnings.Add("$($provider.name) is enabled but has no available sources.")
    }
    if ($provider.enabled -and $stampStatus -ne "fresh") {
        $warnings.Add("$($provider.name) memory index stamp is $stampStatus.")
    }

    $providerReports.Add([ordered]@{
        name = $provider.name
        enabled = [bool]$provider.enabled
        availableSources = [int]$provider.availableSources
        stampPath = $stampPath
        stampStatus = $stampStatus
        stampAgeDays = $stampAgeDays
    })
}

$decision = if ($warnings.Count -eq 0) { "proceed" } else { "review_required" }
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }
$jsonPath = Join-Path $reportRoot "sdlc-memory-lifecycle-report.json"
$mdPath = Join-Path $reportRoot "sdlc-memory-lifecycle-report.md"
$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = $now.ToString("o")
    passed = ($decision -eq "proceed")
    decision = $decision
    contextReportPath = $contextPath
    maxIndexAgeDays = $maxAgeDays
    touchIndex = [bool]$TouchIndex
    warnings = @($warnings)
    providers = @($providerReports)
}
$lines = @(
    "- Decision: $decision",
    "- Providers: $($providerReports.Count)",
    "- Warnings: $($warnings.Count)",
    "- Touch index: $([bool]$TouchIndex)"
)
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Memory Lifecycle Report" -Lines $lines

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
if ($decision -eq "review_required" -and -not $NoExitCode) { exit 2 }
