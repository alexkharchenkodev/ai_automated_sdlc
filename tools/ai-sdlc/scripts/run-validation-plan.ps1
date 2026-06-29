[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $PlanPath = "sdlc-validation-plan.json",
    [string] $JsonOutputPath = "sdlc-selected-validation-report.json",
    [string] $MarkdownOutputPath = "sdlc-selected-validation-report.md",
    [switch] $SkipExecution,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$resolvedPlanPath = if ([System.IO.Path]::IsPathRooted($PlanPath)) { $PlanPath } else { Join-Path $rootPath $PlanPath }
$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json
$results = [System.Collections.Generic.List[object]]::new()
$passed = $true

foreach ($entry in @($plan.commands)) {
    $command = [string]$entry.command
    $started = Get-Date
    $exitCode = 0
    $output = ""
    $status = "skipped"

    if ($SkipExecution -or -not [bool]$entry.required) {
        $status = "skipped"
    } else {
        Push-Location -LiteralPath $rootPath
        try {
            $output = Invoke-Expression "$command 2>&1" | Out-String
            if ($LASTEXITCODE -ne $null) {
                $exitCode = [int]$LASTEXITCODE
            }
            $status = if ($exitCode -eq 0) { "passed" } else { "failed" }
        } catch {
            $exitCode = 1
            $status = "failed"
            $output = $_.Exception.Message
        } finally {
            Pop-Location
        }
    }

    if ($status -eq "failed") {
        $passed = $false
    }

    $results.Add([ordered]@{
        id = $entry.id
        command = $command
        required = [bool]$entry.required
        status = $status
        exitCode = $exitCode
        startedAtUtc = $started.ToUniversalTime().ToString("o")
        finishedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        outputPreview = (($output -split "`r?`n") | Select-Object -First 20) -join "`n"
    })
}

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    planPath = $resolvedPlanPath
    passed = $passed
    skipped = [bool]$SkipExecution
    results = @($results)
}

$lines = @(
    "- Passed: $passed",
    "- Execution skipped: $([bool]$SkipExecution)",
    "- Commands: $($results.Count)"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $rootPath $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $rootPath $MarkdownOutputPath }

Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Selected Validation Report" -Lines $lines

if (-not $passed) {
    $result | ConvertTo-Json -Depth 12
    exit 1
}

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}
