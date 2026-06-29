[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ConfigPath = "",
    [string] $JsonOutputPath = "sdlc-integrations-report.json",
    [string] $MarkdownOutputPath = "sdlc-integrations-report.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/integrations.yaml" }
if (-not (Test-Path -LiteralPath $config)) {
    throw "Integrations config not found: $config"
}

$lines = (Get-Content -LiteralPath $config -Raw) -split "`r?`n"
$integrations = Get-YamlNestedObjectMap -Lines $lines -RootKey "integrations"
$reports = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$enabledCount = 0
$readyCount = 0

foreach ($name in $integrations.Keys) {
    $integration = $integrations[$name]
    $enabled = [bool]$integration.enabled
    if ($enabled) { $enabledCount += 1 }

    $missingEnv = [System.Collections.Generic.List[string]]::new()
    $presentEnv = [System.Collections.Generic.List[string]]::new()
    foreach ($envName in @($integration.required_env)) {
        $envText = [string]$envName
        if ([Environment]::GetEnvironmentVariable($envText)) {
            $presentEnv.Add($envText)
        } else {
            $missingEnv.Add($envText)
        }
    }

    $mcpConfigPath = [string]$integration.mcp_config_path
    $mcpConfigResolved = if ($mcpConfigPath) {
        if ([System.IO.Path]::IsPathRooted($mcpConfigPath)) { $mcpConfigPath } else { Join-Path $rootPath $mcpConfigPath }
    } else {
        ""
    }
    $mcpConfigPresent = if ($mcpConfigResolved) { Test-Path -LiteralPath $mcpConfigResolved } else { $false }

    $status = "disabled"
    if ($enabled) {
        if ($missingEnv.Count -eq 0 -and ([string]$integration.mode -ne "mcp" -or $integration.mcp_server)) {
            $status = "ready"
            $readyCount += 1
        } else {
            $status = "needs_configuration"
            $warnings.Add("$name is enabled but missing required configuration.")
        }
    }

    if ($enabled -and [string]$integration.mode -eq "mcp" -and -not $mcpConfigPresent) {
        $warnings.Add("$name is configured for MCP but the example mcp_config_path was not found.")
    }

    $reports.Add([ordered]@{
        name = $name
        enabled = $enabled
        status = $status
        provider = $integration.provider
        mode = $integration.mode
        mcpServer = $integration.mcp_server
        mcpConfigPath = $mcpConfigPath
        mcpConfigPresent = $mcpConfigPresent
        requiredEnv = @($integration.required_env)
        presentEnv = @($presentEnv)
        missingEnv = @($missingEnv)
        syncDirection = $integration.sync_direction
    })
}

$decision = if ($enabledCount -eq 0) { "proceed" } elseif ($readyCount -eq $enabledCount) { "proceed" } else { "review_required" }

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    configPath = $config
    passed = ($decision -eq "proceed")
    decision = $decision
    enabledIntegrations = $enabledCount
    readyIntegrations = $readyCount
    integrations = @($reports)
    warnings = @($warnings)
}

$mdLines = @(
    "- Decision: $decision",
    "- Enabled integrations: $enabledCount",
    "- Ready integrations: $readyCount",
    "- Warnings: $($warnings.Count)"
)
foreach ($integration in @($reports)) {
    $mdLines += "- $($integration.name): $($integration.status), mode=$($integration.mode), missing_env=$(@($integration.missingEnv).Count)"
}

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $JsonOutputPath -MarkdownPath $MarkdownOutputPath -Title "AI SDLC Integrations Report" -Lines $mdLines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $JsonOutputPath -Raw
}
