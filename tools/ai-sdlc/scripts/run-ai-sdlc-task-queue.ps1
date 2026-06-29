[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ContractsDirectory = ".sdlc/task-contracts",
    [string] $ReportDirectory = ".sdlc/task-queue",
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $SkipApprovalGates,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Write-QueueEvent {
    param(
        [object] $Contract,
        [string] $Role,
        [string] $Status,
        [string] $Message,
        [string[]] $Artifact = @()
    )
    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $Contract.batchId -TaskId $Contract.taskId -TaskTitle $Contract.title -TaskOrder $Contract.taskOrder -Role $Role -Status $Status -Message $Message -Artifact $Artifact -LiveDirectory $LiveDirectory | Out-Null
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$contractsRoot = if ([System.IO.Path]::IsPathRooted($ContractsDirectory)) { $ContractsDirectory } else { Join-Path $rootPath $ContractsDirectory }
if (-not (Test-Path -LiteralPath $contractsRoot)) { throw "Task contracts directory not found: $contractsRoot" }

$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }

$contracts = @(Get-ChildItem -LiteralPath $contractsRoot -Filter "*.json" -File | ForEach-Object {
    $contract = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    $contract | Add-Member -NotePropertyName contractPath -NotePropertyValue $_.FullName -Force
    $contract
} | Sort-Object @{Expression = { [int]$_.taskOrder }}, taskId)

$processed = [System.Collections.Generic.List[object]]::new()
foreach ($contract in $contracts) {
    Write-QueueEvent -Contract $contract -Role "intake" -Status "running" -Message "Task queue picked up contract."
    Write-QueueEvent -Contract $contract -Role "intake" -Status "completed" -Message "Task contract loaded." -Artifact @($contract.contractPath)

    $handoffPairs = @(
        @("ba", "architecture"),
        @("architecture", "memory_reuse"),
        @("memory_reuse", "design"),
        @("design", "engineering")
    )

    $blocked = $false
    foreach ($pair in $handoffPairs) {
        Write-QueueEvent -Contract $contract -Role $pair[0] -Status "completed" -Message "$($pair[0]) work packet prepared."
        $handoffResult = & "$PSScriptRoot/verify-handoff-gate.ps1" -Root $rootPath -FromRole $pair[0] -ToRole $pair[1] -TaskContractPath $contract.contractPath -ReportDirectory (Join-Path $reportRoot "handoffs") -LiveDirectory $LiveDirectory -EmitEvent -NoExitCode | ConvertFrom-Json
        if (-not [bool]$handoffResult.passed) {
            $blocked = $true
            break
        }
    }

    if (-not $blocked -and -not $SkipApprovalGates) {
        $approvalResult = & "$PSScriptRoot/verify-approval-gate.ps1" -Root $rootPath -TaskContractPath $contract.contractPath -Scope "before_implementation" -ReportDirectory (Join-Path $reportRoot "approvals") -LiveDirectory $LiveDirectory -EmitEvent -NoExitCode | ConvertFrom-Json
        if (-not [bool]$approvalResult.passed) { $blocked = $true }
    }

    if (-not $blocked) {
        Write-QueueEvent -Contract $contract -Role "engineering" -Status "completed" -Message "Engineering packet completed by queue runner simulation."
        Write-QueueEvent -Contract $contract -Role "code_review" -Status "completed" -Message "Code review gate completed by queue runner simulation."
        Write-QueueEvent -Contract $contract -Role "test_execution" -Status "completed" -Message "Validation gate completed by queue runner simulation."
        & "$PSScriptRoot/verify-reopen-policy.ps1" -Root $rootPath -TaskId $contract.taskId -ReportDirectory (Join-Path $reportRoot "reopen-policy") -LiveDirectory $LiveDirectory -NoExitCode | Out-Null
        Write-QueueEvent -Contract $contract -Role "evidence" -Status "completed" -Message "Queue evidence generated."
        Write-QueueEvent -Contract $contract -Role "done" -Status "completed" -Message "Task queue item completed." -Artifact @($contract.contractPath)
    }

    $processed.Add([ordered]@{
        taskId = $contract.taskId
        title = $contract.title
        blocked = $blocked
    })
}

& "$PSScriptRoot/check-memory-lifecycle.ps1" -Root $rootPath -ReportDirectory (Join-Path $reportRoot "memory") -TouchIndex -NoExitCode | Out-Null
& "$PSScriptRoot/verify-reopen-policy.ps1" -Root $rootPath -ReportDirectory (Join-Path $reportRoot "reopen-policy") -LiveDirectory $LiveDirectory -NoExitCode | Out-Null

$summary = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    contractsDirectory = $contractsRoot
    reportDirectory = $reportRoot
    taskCount = $contracts.Count
    blockedCount = @($processed | Where-Object { $_.blocked }).Count
    completedCount = @($processed | Where-Object { -not $_.blocked }).Count
    tasks = @($processed)
}
$jsonPath = Join-Path $reportRoot "sdlc-task-queue-summary.json"
$mdPath = Join-Path $reportRoot "sdlc-task-queue-summary.md"
$lines = @(
    "- Tasks: $($contracts.Count)",
    "- Completed: $($summary.completedCount)",
    "- Blocked: $($summary.blockedCount)"
)
Write-SdlcJsonAndMarkdown -Data $summary -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Task Queue Summary" -Lines $lines

if ($Pretty) { $summary | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
if ($summary.blockedCount -gt 0) { exit 2 }
