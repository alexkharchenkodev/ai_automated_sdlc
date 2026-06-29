[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $BatchId = "",
    [string] $TaskId = "",
    [int] $TaskOrder = 1,
    [Parameter(Mandatory = $true)]
    [string] $Title,
    [string] $Description = "",
    [string] $PrimaryTarget = "",
    [string[]] $AcceptanceCriteria = @(),
    [string[]] $NonGoal = @(),
    [string[]] $Dependency = @(),
    [string[]] $ArchitectureBoundary = @(),
    [string[]] $ProtectedSurface = @(),
    [string[]] $ApprovalRequired = @(),
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

$rootPath = Resolve-AiSdlcRoot -Root $Root
if (-not $BatchId) { $BatchId = "batch-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss") }
if (-not $TaskId) { $TaskId = "$(ConvertTo-SafeId -Value $Title)-" + (Get-Date).ToUniversalTime().ToString("HHmmss") }
if (-not $Description) { $Description = $Title }
if (-not $PrimaryTarget) { $PrimaryTarget = "project-configured target" }
if (@($AcceptanceCriteria).Count -eq 0) { $AcceptanceCriteria = @("Requested behavior is implemented and verified.") }
if (@($NonGoal).Count -eq 0) { $NonGoal = @("No unrelated product or framework changes.") }
if (@($Dependency).Count -eq 0) { $Dependency = @("No external dependency declared.") }
if (@($ArchitectureBoundary).Count -eq 0) { $ArchitectureBoundary = @("Respect project-profile architecture areas and protected surfaces.") }
if (@($ProtectedSurface).Count -eq 0) { $ProtectedSurface = @("No protected surface change without approval.") }

$outputRoot = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $rootPath $OutputDirectory }
if (-not (Test-Path -LiteralPath $outputRoot)) {
    New-Item -ItemType Directory -Force -Path $outputRoot | Out-Null
}

$contract = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    batchId = $BatchId
    taskId = $TaskId
    taskOrder = $TaskOrder
    status = "planned"
    taskType = "task"
    parentTaskId = ""
    decompositionRequired = $false
    decompositionStatus = "not_evaluated"
    taskBreakdown = @()
    title = $Title
    description = $Description
    primaryTarget = $PrimaryTarget
    acceptanceCriteria = @($AcceptanceCriteria)
    nonGoals = @($NonGoal)
    dependencies = @($Dependency)
    architectureBoundaries = @($ArchitectureBoundary)
    protectedSurfaces = @($ProtectedSurface)
    approvalsRequired = @($ApprovalRequired)
    reuseEvidence = @("Search configured memory providers and repository before implementation.")
    uxNotes = @("Check user-visible states, accessibility, and existing UI patterns when applicable.")
    implementationNotes = @()
    changedFiles = @()
    reviewFindings = @()
    validationPlan = @("Run configured build/test/lint commands or record a skip reason.")
    validationEvidence = @()
    residualRisk = @()
    evidenceBundle = @()
}

$safeTaskId = ConvertTo-SafeId -Value $TaskId
$jsonPath = Join-Path $outputRoot "$safeTaskId.json"
$mdPath = Join-Path $outputRoot "$safeTaskId.md"
$lines = @(
    "- Batch: $BatchId",
    "- Task: $TaskId",
    "- Order: $TaskOrder",
    "- Title: $Title",
    "- Primary target: $PrimaryTarget",
    "- Acceptance criteria: $(@($AcceptanceCriteria).Count)",
    "- Non-goals: $(@($NonGoal).Count)",
    "- Approvals required: $(@($ApprovalRequired) -join ', ')"
)
Write-SdlcJsonAndMarkdown -Data $contract -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Task Contract" -Lines $lines

if ($EmitEvent) {
    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $BatchId -TaskId $TaskId -TaskTitle $Title -TaskOrder $TaskOrder -Role "intake" -Status "completed" -Message "Task contract created." -Artifact @($jsonPath, $mdPath) -LiveDirectory $LiveDirectory | Out-Null
}

$result = [ordered]@{
    contractPath = $jsonPath
    markdownPath = $mdPath
    contract = $contract
}
if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { $jsonPath }
