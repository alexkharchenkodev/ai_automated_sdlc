[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ConfigPath = "",
    [string] $ImpactReportPath = "sdlc-impact-report.json",
    [string] $ReportDirectory = ".",
    [string] $JsonOutputPath = "sdlc-token-usage-report.json",
    [string] $MarkdownOutputPath = "sdlc-token-usage-report.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Get-EstimatedTokens {
    param(
        [long] $Characters,
        [int] $CharsPerToken
    )

    if ($CharsPerToken -lt 1) { $CharsPerToken = 4 }
    return [int][Math]::Ceiling($Characters / $CharsPerToken)
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/token_budget.yaml" }
if (-not (Test-Path -LiteralPath $config)) {
    throw "Token budget config not found: $config"
}

$configLines = (Get-Content -LiteralPath $config -Raw) -split "`r?`n"
$settings = Get-YamlSectionScalarMap -Lines $configLines -RootKey "settings"
$charsPerToken = if ($settings.chars_per_token) { [int]$settings.chars_per_token } else { 4 }
$warningTokens = if ($settings.warning_tokens) { [int]$settings.warning_tokens } else { 32000 }
$reviewRequiredTokens = if ($settings.review_required_tokens) { [int]$settings.review_required_tokens } else { 96000 }
$blockedTokens = if ($settings.blocked_tokens) { [int]$settings.blocked_tokens } else { 192000 }

$impactPath = if ([System.IO.Path]::IsPathRooted($ImpactReportPath)) { $ImpactReportPath } else { Join-Path $reportRoot $ImpactReportPath }
$impact = if (Test-Path -LiteralPath $impactPath) { Get-Content -LiteralPath $impactPath -Raw | ConvertFrom-Json } else { $null }

$items = [System.Collections.Generic.List[object]]::new()
$totalChars = 0L

if ($impact -and [bool]$settings.include_changed_file_content) {
    foreach ($changedFile in @($impact.changedFiles)) {
        $relative = ConvertTo-SdlcPath -Path ([string]$changedFile)
        $filePath = Join-Path $rootPath $relative
        $chars = 0L
        $status = "missing"
        if (Test-Path -LiteralPath $filePath -PathType Leaf) {
            $chars = (Get-Content -LiteralPath $filePath -Raw).Length
            $status = "counted"
            $totalChars += $chars
        }

        $items.Add([ordered]@{
            kind = "changed_file"
            path = $relative
            status = $status
            characters = $chars
            estimatedTokens = Get-EstimatedTokens -Characters $chars -CharsPerToken $charsPerToken
        })
    }
}

if ([bool]$settings.include_generated_reports -and (Test-Path -LiteralPath $reportRoot)) {
    $generatedReports = Get-ChildItem -LiteralPath $reportRoot -File |
        Where-Object {
            $_.Name -match "^sdlc-.*\.(json|md)$" -and
            $_.Name -ne "sdlc-token-usage-report.json" -and
            $_.Name -ne "sdlc-token-usage-report.md" -and
            $_.Name -ne "sdlc-evidence-bundle.json" -and
            $_.Name -ne "sdlc-evidence-bundle.md" -and
            $_.Name -ne "sdlc-summary.json"
        }
    foreach ($report in $generatedReports) {
        $chars = (Get-Content -LiteralPath $report.FullName -Raw).Length
        $totalChars += $chars
        $items.Add([ordered]@{
            kind = "generated_report"
            path = $report.FullName
            status = "counted"
            characters = $chars
            estimatedTokens = Get-EstimatedTokens -Characters $chars -CharsPerToken $charsPerToken
        })
    }
}

$estimatedTokens = Get-EstimatedTokens -Characters $totalChars -CharsPerToken $charsPerToken
$decision = if ($estimatedTokens -ge $blockedTokens) {
    "blocked"
} elseif ($estimatedTokens -ge $reviewRequiredTokens) {
    "review_required"
} elseif ($estimatedTokens -ge $warningTokens) {
    "warning"
} else {
    "proceed"
}

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    configPath = $config
    passed = ($decision -ne "blocked")
    decision = $decision
    charsPerToken = $charsPerToken
    totalCharacters = $totalChars
    estimatedTokens = $estimatedTokens
    thresholds = [ordered]@{
        warningTokens = $warningTokens
        reviewRequiredTokens = $reviewRequiredTokens
        blockedTokens = $blockedTokens
    }
    countedItems = @($items)
}

$mdLines = @(
    "- Decision: $decision",
    "- Estimated tokens: $estimatedTokens",
    "- Total characters: $totalChars",
    "- Counted items: $($items.Count)",
    "- Warning threshold: $warningTokens",
    "- Review-required threshold: $reviewRequiredTokens",
    "- Blocked threshold: $blockedTokens"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $reportRoot $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $reportRoot $MarkdownOutputPath }

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Token Usage Estimate" -Lines $mdLines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}
