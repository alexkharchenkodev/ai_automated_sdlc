[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ContractsDirectory = ".sdlc/task-contracts",
    [string] $ReportDirectory = ".sdlc/executor",
    [string] $LiveDirectory = ".sdlc/live",
    [string] $ConfigPath = "",
    [ValidateSet("work_order", "external", "simulate")]
    [string] $Mode = "",
    [switch] $SkipApprovalGates,
    [switch] $RequireExecutors,
    [int] $MaxTasks = 0,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Test-ContractValue {
    param([object] $Object, [string] $Path)

    $current = $Object
    foreach ($part in ($Path -split "\.")) {
        if ($null -eq $current) { return $false }
        $property = $current.PSObject.Properties[$part]
        if (-not $property) { return $false }
        $current = $property.Value
    }

    if ($null -eq $current) { return $false }
    if ($current -is [string]) { return -not [string]::IsNullOrWhiteSpace($current) }
    if ($current -is [System.Collections.IEnumerable] -and -not ($current -is [string])) { return @($current).Count -gt 0 }
    return $true
}

function Save-TaskContract {
    param([object] $Contract)

    $path = [string]$Contract.contractPath
    $Contract.PSObject.Properties.Remove("contractPath")
    $Contract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path
    $Contract | Add-Member -NotePropertyName contractPath -NotePropertyValue $path -Force
}

function Ensure-ContractListValue {
    param(
        [object] $Contract,
        [string] $PropertyName,
        [string] $Value
    )

    $property = $Contract.PSObject.Properties[$PropertyName]
    if (-not $property) {
        $Contract | Add-Member -NotePropertyName $PropertyName -NotePropertyValue @($Value) -Force
        return
    }

    if (@($property.Value).Count -eq 0) {
        $property.Value = @($Value)
    }
}

function Write-ExecutorEvent {
    param(
        [object] $Contract,
        [string] $Role,
        [string] $Status,
        [string] $Message,
        [string[]] $Artifact = @(),
        [string] $EventType = "role_progress",
        [string] $ReopenToRole = "",
        [string] $ReopenReason = "",
        [string] $ReopenSeverity = "warning"
    )

    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $Contract.batchId -TaskId $Contract.taskId -TaskTitle $Contract.title -TaskOrder $Contract.taskOrder -Role $Role -Status $Status -Message $Message -Artifact $Artifact -EventType $EventType -ReopenToRole $ReopenToRole -ReopenReason $ReopenReason -ReopenSeverity $ReopenSeverity -LiveDirectory $LiveDirectory | Out-Null
}

function Get-RoleRequiredOutputs {
    param([object] $Executors, [string] $Role)

    if ($Executors.Contains($Role)) {
        return @($Executors[$Role].required_outputs)
    }

    return @()
}

function New-RoleWorkOrder {
    param(
        [object] $Contract,
        [string] $Role,
        [string[]] $RequiredOutputs
    )

    $safeTask = ([string]$Contract.taskId -replace "[^A-Za-z0-9_.-]", "_")
    $taskWorkOrderRoot = Join-Path $workOrderRoot $safeTask
    if (-not (Test-Path -LiteralPath $taskWorkOrderRoot)) {
        New-Item -ItemType Directory -Force -Path $taskWorkOrderRoot | Out-Null
    }

    $roleIndex = [array]::IndexOf($roleSequence, $Role) + 1
    $jsonPath = Join-Path $taskWorkOrderRoot ("{0:00}-{1}.json" -f $roleIndex, $Role)
    $mdPath = Join-Path $taskWorkOrderRoot ("{0:00}-{1}.md" -f $roleIndex, $Role)
    $submitCommand = 'powershell -ExecutionPolicy Bypass -File tools/ai-sdlc/scripts/submit-role-artifact.ps1 -TaskContractPath "{0}" -Role {1} -Append "field=value"' -f $Contract.contractPath, $Role
    $workOrder = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        mode = $Mode
        role = $Role
        taskId = $Contract.taskId
        taskTitle = $Contract.title
        taskOrder = $Contract.taskOrder
        taskContractPath = $Contract.contractPath
        requiredOutputs = @($RequiredOutputs)
        submitCommand = $submitCommand
    }

    $lines = @(
        "- Mode: $Mode",
        "- Role: $Role",
        "- Task: $($Contract.taskId)",
        "- Contract: $($Contract.contractPath)",
        "- Required outputs: $(@($RequiredOutputs) -join ', ')",
        "",
        "Submit results with:",
        "",
        '```powershell',
        $workOrder.submitCommand,
        '```'
    )
    Write-SdlcJsonAndMarkdown -Data $workOrder -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Role Work Order" -Lines $lines
    return [ordered]@{
        jsonPath = $jsonPath
        markdownPath = $mdPath
        workOrder = $workOrder
    }
}

function Expand-ExecutorCommand {
    param(
        [string] $Command,
        [object] $Contract,
        [string] $Role,
        [string] $WorkOrderPath
    )

    $expanded = $Command
    $tokens = @{
        "{{root}}" = $rootPath
        "{{task_contract}}" = [string]$Contract.contractPath
        "{{task_id}}" = [string]$Contract.taskId
        "{{role}}" = $Role
        "{{work_order}}" = $WorkOrderPath
        "{{result_directory}}" = $resultRoot
        "{{live_directory}}" = (Get-AiSdlcLiveDirectory -Root $rootPath -LiveDirectory $LiveDirectory)
    }

    foreach ($token in $tokens.Keys) {
        $expanded = $expanded.Replace($token, $tokens[$token])
    }

    return $expanded
}

function Invoke-ExternalRoleCommand {
    param(
        [object] $Contract,
        [string] $Role,
        [string] $Command,
        [string] $WorkOrderPath
    )

    $expanded = Expand-ExecutorCommand -Command $Command -Contract $Contract -Role $Role -WorkOrderPath $WorkOrderPath
    $safeTask = ([string]$Contract.taskId -replace "[^A-Za-z0-9_.-]", "_")
    $roleResultRoot = Join-Path $resultRoot $safeTask
    if (-not (Test-Path -LiteralPath $roleResultRoot)) {
        New-Item -ItemType Directory -Force -Path $roleResultRoot | Out-Null
    }

    $stdoutPath = Join-Path $roleResultRoot "$Role.stdout.txt"
    $stderrPath = Join-Path $roleResultRoot "$Role.stderr.txt"
    $started = (Get-Date).ToUniversalTime()
    $process = Start-Process -FilePath "powershell" -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $expanded) -NoNewWindow -PassThru -Wait -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
    $finished = (Get-Date).ToUniversalTime()

    $result = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = $finished.ToString("o")
        taskId = $Contract.taskId
        role = $Role
        command = $expanded
        exitCode = $process.ExitCode
        startedAtUtc = $started.ToString("o")
        finishedAtUtc = $finished.ToString("o")
        stdoutPath = $stdoutPath
        stderrPath = $stderrPath
    }
    $resultPath = Join-Path $roleResultRoot "$Role.result.json"
    $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resultPath
    return $result
}

function Invoke-ExecutorTransition {
    param([object] $Contract, [string] $Role)

    $transition = $null
    foreach ($candidate in $roleTransitions) {
        if ($candidate[0] -eq $Role) {
            $transition = $candidate
            break
        }
    }

    if ($null -eq $transition) { return $true }

    $handoffResult = & "$PSScriptRoot/verify-handoff-gate.ps1" -Root $rootPath -FromRole $transition[0] -ToRole $transition[1] -TaskContractPath $Contract.contractPath -ReportDirectory (Join-Path $reportRoot "handoffs") -LiveDirectory $LiveDirectory -EmitEvent -NoExitCode | ConvertFrom-Json
    return [bool]$handoffResult.passed
}

function Test-ImplementationApproval {
    param([object] $Contract, [string] $Role)

    if ($Role -ne "design" -or $SkipApprovalGates) { return "proceed" }

    $approvalResult = & "$PSScriptRoot/verify-approval-gate.ps1" -Root $rootPath -TaskContractPath $Contract.contractPath -Scope "before_implementation" -ReportDirectory (Join-Path $reportRoot "approvals") -LiveDirectory $LiveDirectory -EmitEvent -NoExitCode | ConvertFrom-Json
    if ([bool]$approvalResult.passed) { return "proceed" }
    return "waiting"
}

function Set-SimulatedRoleOutputs {
    param([object] $Contract, [string] $Role)

    switch ($Role) {
        "ba" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "acceptanceCriteria" -Value "Executor simulation confirmed acceptance criteria."
            Ensure-ContractListValue -Contract $Contract -PropertyName "nonGoals" -Value "Executor simulation confirmed non-goals."
        }
        "architecture" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "architectureBoundaries" -Value "Executor simulation confirmed architecture boundaries."
            Ensure-ContractListValue -Contract $Contract -PropertyName "protectedSurfaces" -Value "Executor simulation confirmed protected surfaces."
            Ensure-ContractListValue -Contract $Contract -PropertyName "dependencies" -Value "Executor simulation confirmed dependencies."
        }
        "memory_reuse" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "reuseEvidence" -Value "Executor simulation recorded reuse evidence."
        }
        "design" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "uxNotes" -Value "Executor simulation recorded UX notes."
            Ensure-ContractListValue -Contract $Contract -PropertyName "validationPlan" -Value "Executor simulation recorded validation plan."
        }
        "engineering" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "implementationNotes" -Value "Executor simulation recorded implementation notes."
            Ensure-ContractListValue -Contract $Contract -PropertyName "changedFiles" -Value "Executor simulation did not modify product files."
            Ensure-ContractListValue -Contract $Contract -PropertyName "validationPlan" -Value "Executor simulation retained validation plan."
        }
        "code_review" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "reviewFindings" -Value "Executor simulation found no blocking review issue."
        }
        "test_planning" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "validationPlan" -Value "Executor simulation selected validation."
        }
        "test_execution" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "validationEvidence" -Value "Executor simulation recorded validation evidence."
            Ensure-ContractListValue -Contract $Contract -PropertyName "residualRisk" -Value "Executor simulation recorded no residual risk."
        }
        "evidence" {
            Ensure-ContractListValue -Contract $Contract -PropertyName "evidenceBundle" -Value "Executor simulation generated evidence bundle placeholder."
            Ensure-ContractListValue -Contract $Contract -PropertyName "residualRisk" -Value "Executor simulation recorded no residual risk."
        }
    }
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/role_executors.yaml" }
if (-not (Test-Path -LiteralPath $config)) { throw "Role executor config not found: $config" }

$configLines = (Get-Content -LiteralPath $config -Raw) -split "`r?`n"
$settings = Get-YamlSectionScalarMap -Lines $configLines -RootKey "settings"
$executors = Get-YamlNestedObjectMap -Lines $configLines -RootKey "role_executors"
if (-not $Mode) {
    $Mode = if ($settings.default_mode) { [string]$settings.default_mode } else { "work_order" }
}

$contractsRoot = if ([System.IO.Path]::IsPathRooted($ContractsDirectory)) { $ContractsDirectory } else { Join-Path $rootPath $ContractsDirectory }
if (-not (Test-Path -LiteralPath $contractsRoot)) { throw "Task contracts directory not found: $contractsRoot" }
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }

$workOrderDirectory = if ($settings.work_order_directory) { [string]$settings.work_order_directory } else { ".sdlc/executor/work-orders" }
$resultDirectory = if ($settings.result_directory) { [string]$settings.result_directory } else { ".sdlc/executor/results" }
$workOrderRoot = if ([System.IO.Path]::IsPathRooted($workOrderDirectory)) { $workOrderDirectory } else { Join-Path $rootPath $workOrderDirectory }
$resultRoot = if ([System.IO.Path]::IsPathRooted($resultDirectory)) { $resultDirectory } else { Join-Path $rootPath $resultDirectory }
foreach ($directory in @($workOrderRoot, $resultRoot)) {
    if (-not (Test-Path -LiteralPath $directory)) { New-Item -ItemType Directory -Force -Path $directory | Out-Null }
}

$roleSequence = @("ba", "architecture", "memory_reuse", "design", "engineering", "code_review", "test_planning", "test_execution", "evidence")
$roleTransitions = @(
    @("ba", "architecture"),
    @("architecture", "memory_reuse"),
    @("memory_reuse", "design"),
    @("design", "engineering"),
    @("engineering", "code_review"),
    @("code_review", "test_planning"),
    @("test_planning", "test_execution"),
    @("test_execution", "evidence"),
    @("evidence", "done")
)

$contracts = @(Get-ChildItem -LiteralPath $contractsRoot -Filter "*.json" -File | ForEach-Object {
    $contract = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
    $contract | Add-Member -NotePropertyName contractPath -NotePropertyValue $_.FullName -Force
    $contract
} | Sort-Object @{Expression = { [int]$_.taskOrder }}, taskId)
if ($MaxTasks -gt 0) { $contracts = @($contracts | Select-Object -First $MaxTasks) }

$processed = [System.Collections.Generic.List[object]]::new()
foreach ($contract in $contracts) {
    $blocked = $false
    $waiting = $false
    $roleReports = [System.Collections.Generic.List[object]]::new()
    Write-ExecutorEvent -Contract $contract -Role "intake" -Status "completed" -Message "Executor loaded task contract." -Artifact @($contract.contractPath)

    foreach ($role in $roleSequence) {
        $requiredOutputs = Get-RoleRequiredOutputs -Executors $executors -Role $role
        $missingBefore = @($requiredOutputs | Where-Object { -not (Test-ContractValue -Object $contract -Path ([string]$_)) })
        if ($Mode -ne "simulate" -and $missingBefore.Count -eq 0) {
            Write-ExecutorEvent -Contract $contract -Role $role -Status "completed" -Message "Executor found existing outputs for $role and continued."
            if (-not (Invoke-ExecutorTransition -Contract $contract -Role $role)) {
                $blocked = $true
                break
            }

            $approvalDecision = Test-ImplementationApproval -Contract $contract -Role $role
            if ($approvalDecision -eq "waiting") {
                $waiting = $true
                break
            }

            continue
        }

        $workOrderInfo = New-RoleWorkOrder -Contract $contract -Role $role -RequiredOutputs $requiredOutputs
        Write-ExecutorEvent -Contract $contract -Role $role -Status "running" -Message "Executor prepared role work order for $role." -Artifact @($workOrderInfo.jsonPath, $workOrderInfo.markdownPath)

        if ($Mode -eq "simulate") {
            Set-SimulatedRoleOutputs -Contract $contract -Role $role
            Save-TaskContract -Contract $contract
            Write-ExecutorEvent -Contract $contract -Role $role -Status "completed" -Message "Executor simulation completed $role outputs." -Artifact @($contract.contractPath)
        } elseif ($Mode -eq "external") {
            $executor = if ($executors.Contains($role)) { $executors[$role] } else { $null }
            $enabled = $executor -and [bool]$executor.enabled -and -not [string]::IsNullOrWhiteSpace([string]$executor.command)
            if ($enabled) {
                $commandResult = Invoke-ExternalRoleCommand -Contract $contract -Role $role -Command ([string]$executor.command) -WorkOrderPath ([string]$workOrderInfo.jsonPath)
                if ([int]$commandResult.exitCode -ne 0) {
                    Write-ExecutorEvent -Contract $contract -Role $role -Status "failed" -Message "External executor failed for $role with exit code $($commandResult.exitCode)." -Artifact @($commandResult.stdoutPath, $commandResult.stderrPath)
                    $blocked = $true
                    break
                }

                $contract = Get-Content -LiteralPath $contract.contractPath -Raw | ConvertFrom-Json
                $contract | Add-Member -NotePropertyName contractPath -NotePropertyValue $workOrderInfo.workOrder.taskContractPath -Force
                Write-ExecutorEvent -Contract $contract -Role $role -Status "completed" -Message "External executor completed $role." -Artifact @($commandResult.stdoutPath, $commandResult.stderrPath)
            } else {
                $status = if ($RequireExecutors -or [bool]$settings.fail_on_missing_executor) { "blocked" } else { "waiting" }
                Write-ExecutorEvent -Contract $contract -Role $role -Status $status -Message "No external executor configured for $role. Work order is ready." -Artifact @($workOrderInfo.jsonPath)
                if ($status -eq "blocked") { $blocked = $true } else { $waiting = $true }
                break
            }
        } else {
            Write-ExecutorEvent -Contract $contract -Role $role -Status "waiting" -Message "Work order is ready for $role. Submit role artifacts to continue." -Artifact @($workOrderInfo.jsonPath, $workOrderInfo.markdownPath)
            $waiting = $true
            break
        }

        $missingOutputs = @($requiredOutputs | Where-Object { -not (Test-ContractValue -Object $contract -Path ([string]$_)) })
        $roleReports.Add([ordered]@{
            role = $role
            workOrderPath = $workOrderInfo.jsonPath
            requiredOutputs = @($requiredOutputs)
            missingOutputs = @($missingOutputs)
        })
        if ($missingOutputs.Count -gt 0) {
            Write-ExecutorEvent -Contract $contract -Role $role -Status "revision_requested" -EventType "reopen" -ReopenToRole $role -ReopenReason "Missing executor outputs: $(@($missingOutputs) -join ', ')" -ReopenSeverity "warning" -Message "Missing executor outputs for $role." -Artifact @($workOrderInfo.jsonPath)
            $blocked = $true
            break
        }

        if (-not (Invoke-ExecutorTransition -Contract $contract -Role $role)) {
            $blocked = $true
            break
        }

        $approvalDecision = Test-ImplementationApproval -Contract $contract -Role $role
        if ($approvalDecision -eq "waiting") {
            $waiting = $true
            break
        }
    }

    if (-not $blocked -and -not $waiting) {
        & "$PSScriptRoot/verify-reopen-policy.ps1" -Root $rootPath -TaskId $contract.taskId -ReportDirectory (Join-Path $reportRoot "reopen-policy") -LiveDirectory $LiveDirectory -NoExitCode | Out-Null
        Write-ExecutorEvent -Contract $contract -Role "done" -Status "completed" -Message "Executor completed all role gates." -Artifact @($contract.contractPath)
    }

    $processed.Add([ordered]@{
        taskId = $contract.taskId
        title = $contract.title
        blocked = $blocked
        waiting = $waiting
        roleReports = @($roleReports)
    })
}

$summary = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    mode = $Mode
    contractsDirectory = $contractsRoot
    reportDirectory = $reportRoot
    workOrderDirectory = $workOrderRoot
    resultDirectory = $resultRoot
    taskCount = $contracts.Count
    completedCount = @($processed | Where-Object { -not $_.blocked -and -not $_.waiting }).Count
    waitingCount = @($processed | Where-Object { $_.waiting }).Count
    blockedCount = @($processed | Where-Object { $_.blocked }).Count
    tasks = @($processed)
}
$jsonPath = Join-Path $reportRoot "sdlc-executor-summary.json"
$mdPath = Join-Path $reportRoot "sdlc-executor-summary.md"
$lines = @(
    "- Mode: $Mode",
    "- Tasks: $($summary.taskCount)",
    "- Completed: $($summary.completedCount)",
    "- Waiting: $($summary.waitingCount)",
    "- Blocked: $($summary.blockedCount)"
)
Write-SdlcJsonAndMarkdown -Data $summary -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Executor Summary" -Lines $lines

if ($Pretty) { $summary | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
if ($summary.blockedCount -gt 0) { exit 1 }
if ($summary.waitingCount -gt 0) { exit 2 }
