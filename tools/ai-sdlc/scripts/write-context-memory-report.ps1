[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ConfigPath = "",
    [string] $JsonOutputPath = "sdlc-context-memory-report.json",
    [string] $MarkdownOutputPath = "sdlc-context-memory-report.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/context_memory.yaml" }
if (-not (Test-Path -LiteralPath $config)) {
    throw "Context memory config not found: $config"
}

$lines = (Get-Content -LiteralPath $config -Raw) -split "`r?`n"
$providers = Get-YamlNestedObjectMap -Lines $lines -RootKey "providers"
$settings = Get-YamlSectionScalarMap -Lines $lines -RootKey "settings"
$providerReports = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$enabledCount = 0
$availableSourceCount = 0

foreach ($name in $providers.Keys) {
    $provider = $providers[$name]
    $enabled = [bool]$provider.enabled
    if ($enabled) { $enabledCount += 1 }

    $sourceReports = [System.Collections.Generic.List[object]]::new()
    $existingSources = 0
    foreach ($source in @($provider.paths)) {
        $sourceText = [string]$source
        $mode = [string]$provider.mode
        $status = "missing"
        $fullPath = ""

        if ($mode -eq "integration") {
            $status = "integration_reference"
            $fullPath = $sourceText
        } else {
            $fullPath = if ([System.IO.Path]::IsPathRooted($sourceText)) { $sourceText } else { Join-Path $rootPath $sourceText }
            if (Test-Path -LiteralPath $fullPath) {
                $status = "available"
                $existingSources += 1
                $availableSourceCount += 1
            }
        }

        $sourceReports.Add([ordered]@{
            path = $sourceText
            resolvedPath = $fullPath
            status = $status
        })
    }

    if ($enabled -and @($provider.paths).Count -gt 0 -and $existingSources -eq 0 -and [string]$provider.mode -ne "integration") {
        $warnings.Add("$name is enabled but none of its configured local sources exist.")
    }

    $providerReports.Add([ordered]@{
        name = $name
        enabled = $enabled
        mode = $provider.mode
        configuredSources = @($provider.paths).Count
        availableSources = $existingSources
        sources = @($sourceReports)
    })
}

if ($enabledCount -eq 0) {
    $warnings.Add("No context or memory providers are enabled.")
}

$decision = if ($enabledCount -eq 0 -and [bool]$settings.require_context_report) { "review_required" } else { "proceed" }

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    configPath = $config
    passed = ($decision -eq "proceed")
    decision = $decision
    enabledProviders = $enabledCount
    availableSources = $availableSourceCount
    settings = $settings
    providers = @($providerReports)
    warnings = @($warnings)
}

$mdLines = @(
    "- Decision: $decision",
    "- Enabled providers: $enabledCount",
    "- Available local sources: $availableSourceCount",
    "- Warnings: $($warnings.Count)"
)
foreach ($provider in @($providerReports)) {
    $mdLines += "- $($provider.name): enabled=$($provider.enabled), mode=$($provider.mode), available=$($provider.availableSources)/$($provider.configuredSources)"
}

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $JsonOutputPath -MarkdownPath $MarkdownOutputPath -Title "AI SDLC Context And Memory Report" -Lines $mdLines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $JsonOutputPath -Raw
}
