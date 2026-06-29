[CmdletBinding()]
param(
    [string] $Root = ".",
    [Parameter(Mandatory = $true)]
    [string] $TaskContractPath,
    [string] $ConfigPath = "",
    [string] $OutputDirectory = ".sdlc/task-contracts",
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $EmitEvent,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function ConvertTo-SafeId {
    param([string] $Value)
    $safe = ($Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
    if (-not $safe) { return "task" }
    return $safe
}

function Get-DefaultSlices {
    param([string[]] $Lines)

    $slices = [System.Collections.Generic.List[object]]::new()
    $inside = $false
    $current = $null
    foreach ($line in $Lines) {
        if ($line -match "^default_slices:\s*$") {
            $inside = $true
            continue
        }
        if ($inside -and $line -match "^\S") { break }
        if (-not $inside) { continue }

        if ($line -match "^\s{2}-\s*id:\s*(.+?)\s*$") {
            if ($null -ne $current) { $slices.Add($current) }
            $current = [ordered]@{ id = Normalize-YamlValue -Value $Matches[1]; title = "" }
            continue
        }
        if ($null -ne $current -and $line -match "^\s{4}title:\s*(.+?)\s*$") {
            $current.title = Normalize-YamlValue -Value $Matches[1]
        }
    }
    if ($null -ne $current) { $slices.Add($current) }
    return @($slices)
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$contractPath = if ([System.IO.Path]::IsPathRooted($TaskContractPath)) { $TaskContractPath } else { Join-Path $rootPath $TaskContractPath }
if (-not (Test-Path -LiteralPath $contractPath)) { throw "Task contract not found: $contractPath" }

$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/task_decomposition.yaml" }
if (-not (Test-Path -LiteralPath $config)) { throw "Task decomposition config not found: $config" }

$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $rootPath $OutputDirectory }
if (-not (Test-Path -LiteralPath $outputRoot)) { New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null }

$configLines = (Get-Content -LiteralPath $config -Raw) -split "`r?`n"
$slices = Get-DefaultSlices -Lines $configLines
if ($slices.Count -eq 0) { throw "No default_slices configured in $config" }

$parent = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$parentId = [string]$parent.taskId
$batchId = if ($parent.batchId) { [string]$parent.batchId } else { "batch-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss") }
$baseOrder = if ($parent.taskOrder) { [int]$parent.taskOrder } else { 1 }

$breakdown = [System.Collections.Generic.List[object]]::new()
$created = [System.Collections.Generic.List[object]]::new()
$index = 1
foreach ($slice in $slices) {
    $childId = "$parentId-$($slice.id)"
    $childOrder = ($baseOrder * 100) + $index
    $title = [string]$slice.title
    $child = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        batchId = $batchId
        taskId = $childId
        parentTaskId = $parentId
        taskType = "subtask"
        taskOrder = $childOrder
        status = "planned"
        title = $title
        description = "$title for parent task: $($parent.title)"
        primaryTarget = $parent.primaryTarget
        acceptanceCriteria = @("Complete this slice without implementing unrelated slices.", "Attach validation or review evidence for this slice.")
        nonGoals = @("Do not collapse multiple sibling slices into this task.")
        dependencies = @("Parent task: $parentId")
        architectureBoundaries = @($parent.architectureBoundaries)
        protectedSurfaces = @($parent.protectedSurfaces)
        approvalsRequired = @()
        decompositionRequired = $false
        decompositionStatus = "not_required"
        taskBreakdown = @()
        reuseEvidence = @("Search existing project files and prior sibling outputs before implementing this slice.")
        uxNotes = @("Confirm UX states for this slice when user-facing.")
        implementationNotes = @()
        changedFiles = @()
        reviewFindings = @()
        validationPlan = @("Run slice-relevant validation and update evidence.")
        validationEvidence = @()
        residualRisk = @()
        evidenceBundle = @()
    }

    $safeChildId = ConvertTo-SafeId -Value $childId
    $childPath = Join-Path $outputRoot "$safeChildId.json"
    $childMd = Join-Path $outputRoot "$safeChildId.md"
    $childLines = @(
        "- Parent: $parentId",
        "- Child: $childId",
        "- Order: $childOrder",
        "- Title: $title",
        "- Slice: $($slice.id)"
    )
    Write-SdlcJsonAndMarkdown -Data $child -JsonPath $childPath -MarkdownPath $childMd -Title "AI SDLC Child Task Contract" -Lines $childLines
    $breakdown.Add([ordered]@{ taskId = $childId; title = $title; order = $childOrder; path = $childPath })
    $created.Add([ordered]@{ taskId = $childId; path = $childPath; markdownPath = $childMd })
    $index += 1
}

$parent | Add-Member -NotePropertyName taskType -NotePropertyValue "epic" -Force
$parent | Add-Member -NotePropertyName decompositionRequired -NotePropertyValue $true -Force
$parent | Add-Member -NotePropertyName decompositionStatus -NotePropertyValue "decomposed" -Force
$parent | Add-Member -NotePropertyName taskBreakdown -NotePropertyValue @($breakdown) -Force
$parent | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $contractPath

$reportRoot = Join-Path $rootPath ".sdlc/decomposition"
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }
$safeParent = ConvertTo-SafeId -Value $parentId
$reportPath = Join-Path $reportRoot "sdlc-task-breakdown-$safeParent.json"
$reportMd = Join-Path $reportRoot "sdlc-task-breakdown-$safeParent.md"
$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    parentTaskId = $parentId
    parentContractPath = $contractPath
    childTaskCount = $created.Count
    children = @($created)
}
$lines = @(
    "- Parent task: $parentId",
    "- Child tasks: $($created.Count)"
)
foreach ($childInfo in $created) { $lines += "- $($childInfo.taskId)" }
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $reportPath -MarkdownPath $reportMd -Title "AI SDLC Task Breakdown" -Lines $lines

if ($EmitEvent) {
    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $batchId -TaskId $parentId -TaskTitle $parent.title -TaskOrder $baseOrder -Role "ba" -Status "completed" -Message "BA decomposed complex task into $($created.Count) child tasks." -Artifact @($reportPath) -LiveDirectory $LiveDirectory | Out-Null
    foreach ($childInfo in $created) {
        $childTaskId = [string]$childInfo.taskId
        $breakdownEntry = @($breakdown | Where-Object { $_["taskId"] -eq $childTaskId } | Select-Object -First 1)
        $childTitle = if ($breakdownEntry) { [string]$breakdownEntry[0]["title"] } else { $childTaskId }
        $childOrder = if ($breakdownEntry) { [int]$breakdownEntry[0]["order"] } else { $baseOrder }
        & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $batchId -TaskId $childTaskId -TaskTitle $childTitle -TaskOrder $childOrder -Role "intake" -Status "pending" -Message "Child task queued by BA decomposition." -Artifact @([string]$childInfo.path) -LiveDirectory $LiveDirectory | Out-Null
    }
}

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $reportPath -Raw }
