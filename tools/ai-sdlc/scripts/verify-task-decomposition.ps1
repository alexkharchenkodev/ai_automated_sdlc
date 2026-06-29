[CmdletBinding()]
param(
    [string] $Root = ".",
    [Parameter(Mandatory = $true)]
    [string] $TaskContractPath,
    [string] $ConfigPath = "",
    [string] $ReportDirectory = ".sdlc/decomposition",
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $EmitEvent,
    [switch] $NoExitCode,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Test-Truthy {
    param([object] $Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    return "$Value" -match "^(true|yes|1)$"
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$contractPath = if ([System.IO.Path]::IsPathRooted($TaskContractPath)) { $TaskContractPath } else { Join-Path $rootPath $TaskContractPath }
if (-not (Test-Path -LiteralPath $contractPath)) { throw "Task contract not found: $contractPath" }

$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/task_decomposition.yaml" }
if (-not (Test-Path -LiteralPath $config)) { throw "Task decomposition config not found: $config" }

$configLines = (Get-Content -LiteralPath $config -Raw) -split "`r?`n"
$settings = Get-YamlSectionScalarMap -Lines $configLines -RootKey "settings"
$keywords = @(Get-YamlTopLevelList -Lines $configLines -Key "complexity_keywords")
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json

$text = @(
    $contract.title,
    $contract.description,
    @($contract.acceptanceCriteria) -join " ",
    @($contract.implementationNotes) -join " "
) -join " "
$normalizedText = $text.ToLowerInvariant()

$detectedKeywords = @($keywords | Where-Object { $normalizedText.Contains(([string]$_).ToLowerInvariant()) })
$acceptanceCount = @($contract.acceptanceCriteria).Count
$minAcceptance = if ($settings.min_acceptance_criteria_for_complexity) { [int]$settings.min_acceptance_criteria_for_complexity } else { 5 }
$minSlices = if ($settings.min_detected_slices_for_complexity) { [int]$settings.min_detected_slices_for_complexity } else { 3 }
$complexByText = ($detectedKeywords.Count -ge $minSlices -or $acceptanceCount -ge $minAcceptance)
$explicitRequired = Test-Truthy -Value $contract.decompositionRequired
$hasBreakdown = @($contract.taskBreakdown).Count -gt 0
$taskType = if ($contract.taskType) { [string]$contract.taskType } else { "task" }
$decompositionStatus = if ($contract.decompositionStatus) { [string]$contract.decompositionStatus } else { "none" }

$contractsRoot = Split-Path -Parent $contractPath
$children = @()
if ($contract.taskId) {
    $children = @(Get-ChildItem -LiteralPath $contractsRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $candidate = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
            if ($candidate.parentTaskId -eq $contract.taskId) { $candidate }
        } catch {
            $null
        }
    } | Where-Object { $_ })
}

$requiresDecomposition = ($explicitRequired -or $complexByText) -and $taskType -ne "subtask"
$isDecomposedParent = ($taskType -eq "epic" -and $decompositionStatus -eq "decomposed" -and $children.Count -gt 0)
$passed = (-not $requiresDecomposition) -or $hasBreakdown -or $children.Count -gt 0 -or $isDecomposedParent
$decision = if ($isDecomposedParent) {
    "decomposed_parent"
} elseif ($passed) {
    "proceed"
} else {
    "decomposition_required"
}

$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }
$safeTask = ([string]$contract.taskId -replace "[^A-Za-z0-9_.-]", "_")
$jsonPath = Join-Path $reportRoot "sdlc-task-decomposition-$safeTask.json"
$mdPath = Join-Path $reportRoot "sdlc-task-decomposition-$safeTask.md"

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    taskId = $contract.taskId
    taskTitle = $contract.title
    taskType = $taskType
    passed = $passed
    decision = $decision
    requiresDecomposition = $requiresDecomposition
    acceptanceCriteriaCount = $acceptanceCount
    detectedKeywords = @($detectedKeywords)
    taskBreakdownCount = @($contract.taskBreakdown).Count
    childTaskCount = $children.Count
    contractPath = $contractPath
}
$lines = @(
    "- Decision: $decision",
    "- Task: $($contract.taskId)",
    "- Requires decomposition: $requiresDecomposition",
    "- Acceptance criteria: $acceptanceCount",
    "- Detected complexity keywords: $($detectedKeywords.Count)",
    "- Child tasks: $($children.Count)"
)
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Task Decomposition Gate" -Lines $lines

if ($EmitEvent -and $decision -eq "decomposition_required") {
    $reason = "BA decomposition required before implementation. Detected $($detectedKeywords.Count) complexity signals and $acceptanceCount acceptance criteria."
    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $contract.batchId -TaskId $contract.taskId -TaskTitle $contract.title -TaskOrder $contract.taskOrder -Role "ba" -Status "revision_requested" -EventType "reopen" -ReopenToRole "ba" -ReopenReason $reason -ReopenSeverity "blocked" -Message $reason -Artifact @($jsonPath) -LiveDirectory $LiveDirectory | Out-Null
}

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
if (-not $NoExitCode) {
    if ($decision -eq "decomposition_required") { exit 2 }
}

