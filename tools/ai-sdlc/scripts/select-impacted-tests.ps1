[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ImpactReportPath = "sdlc-impact-report.json",
    [string] $JsonOutputPath = "sdlc-impacted-tests.json",
    [string] $MarkdownOutputPath = "sdlc-impacted-tests.md",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$impactPath = if ([System.IO.Path]::IsPathRooted($ImpactReportPath)) { $ImpactReportPath } else { Join-Path $rootPath $ImpactReportPath }
$impact = Get-Content -LiteralPath $impactPath -Raw | ConvertFrom-Json

$suggestions = [System.Collections.Generic.List[object]]::new()
foreach ($file in @($impact.changedFiles)) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file)
    $directory = [System.IO.Path]::GetDirectoryName(($file -replace "/", [System.IO.Path]::DirectorySeparatorChar))
    $candidates = [System.Collections.Generic.List[string]]::new()

    if ($baseName) {
        $candidates.Add("**/$baseName.test.*")
        $candidates.Add("**/$baseName.spec.*")
        $candidates.Add("**/${baseName}Tests.*")
    }

    if ($directory) {
        $candidates.Add("$($directory -replace "\\", "/")/**/__tests__/**")
    }

    if ($file -match "api|route|controller|schema|contract|openapi|swagger") {
        $candidates.Add("contract tests")
        $candidates.Add("API integration tests")
    }

    if ($file -match "component|screen|view|page|ui") {
        $candidates.Add("UI component tests")
        $candidates.Add("visual or interaction smoke")
    }

    $suggestions.Add([ordered]@{
        changedFile = $file
        candidates = @($candidates)
    })
}

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    impactReportPath = $impactPath
    suggestions = @($suggestions)
}

$lines = @("- Suggested impacted-test candidates: $($suggestions.Count)", "")
foreach ($suggestion in $suggestions) {
    $lines += "## $($suggestion.changedFile)"
    foreach ($candidate in @($suggestion.candidates)) {
        $lines += "- $candidate"
    }
    $lines += ""
}

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $rootPath $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $rootPath $MarkdownOutputPath }
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Impacted Tests" -Lines $lines

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
