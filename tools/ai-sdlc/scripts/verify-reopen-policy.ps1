[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $TaskId = "",
    [string] $ConfigPath = "",
    [string] $LiveDirectory = ".sdlc/live",
    [string] $ReportDirectory = ".sdlc/reopen-policy",
    [switch] $NoExitCode,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/reopen_policy.yaml" }
if (-not (Test-Path -LiteralPath $config)) { throw "Reopen policy config not found: $config" }
$settings = Get-YamlSectionScalarMap -Lines ((Get-Content -LiteralPath $config -Raw) -split "`r?`n") -RootKey "settings"
$maxPerTask = if ($settings.max_reopens_per_task) { [int]$settings.max_reopens_per_task } else { 3 }
$maxPerPair = if ($settings.max_reopens_per_role_pair) { [int]$settings.max_reopens_per_role_pair } else { 2 }
$blockOnCritical = if ($settings.Contains("block_on_critical_reopen")) { [bool]$settings.block_on_critical_reopen } else { $true }
$requireReason = if ($settings.Contains("require_reason")) { [bool]$settings.require_reason } else { $true }

$liveRoot = Get-AiSdlcLiveDirectory -Root $rootPath -LiveDirectory $LiveDirectory
$eventsPath = Join-Path $liveRoot "events.jsonl"
$events = @()
if (Test-Path -LiteralPath $eventsPath) {
    $events = @(Get-Content -LiteralPath $eventsPath | Where-Object { $_.Trim() } | ForEach-Object { $_ | ConvertFrom-Json })
}
$reopens = @($events | Where-Object {
    ($_.eventType -eq "reopen" -or $_.status -eq "reopened" -or $_.status -eq "revision_requested") -and
    (-not $TaskId -or $_.taskId -eq $TaskId)
})

$pairCounts = [ordered]@{}
$missingReason = 0
$critical = 0
foreach ($event in $reopens) {
    $to = if ($event.reopen -and $event.reopen.toRole) { [string]$event.reopen.toRole } else { "" }
    $key = "$($event.role)->$to"
    if (-not $pairCounts.Contains($key)) { $pairCounts[$key] = 0 }
    $pairCounts[$key] += 1
    if ($requireReason -and (-not $event.reopen -or [string]::IsNullOrWhiteSpace([string]$event.reopen.reason))) { $missingReason += 1 }
    if ($event.reopen -and $event.reopen.severity -eq "critical") { $critical += 1 }
}

$pairViolations = @($pairCounts.Keys | Where-Object { [int]$pairCounts[$_] -gt $maxPerPair })
$decision = "proceed"
if ($reopens.Count -gt $maxPerTask -or $pairViolations.Count -gt 0 -or $missingReason -gt 0) { $decision = "review_required" }
if ($blockOnCritical -and $critical -gt 0) { $decision = "blocked" }
$passed = $decision -eq "proceed"

$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }
$safeTask = if ($TaskId) { ($TaskId -replace "[^A-Za-z0-9_.-]", "_") } else { "all-tasks" }
$jsonPath = Join-Path $reportRoot "sdlc-reopen-policy-$safeTask.json"
$mdPath = Join-Path $reportRoot "sdlc-reopen-policy-$safeTask.md"

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    taskId = $TaskId
    passed = $passed
    decision = $decision
    reopenCount = $reopens.Count
    maxReopensPerTask = $maxPerTask
    maxReopensPerRolePair = $maxPerPair
    missingReasonCount = $missingReason
    criticalReopenCount = $critical
    rolePairCounts = $pairCounts
    rolePairViolations = @($pairViolations)
}
$lines = @(
    "- Decision: $decision",
    "- Task: $(if ($TaskId) { $TaskId } else { 'all tasks' })",
    "- Reopens: $($reopens.Count)",
    "- Pair violations: $($pairViolations.Count)",
    "- Missing reasons: $missingReason",
    "- Critical reopens: $critical"
)
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Reopen Policy Report" -Lines $lines

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
if (-not $NoExitCode) {
    if ($decision -eq "blocked") { exit 1 }
    if ($decision -eq "review_required") { exit 2 }
}
