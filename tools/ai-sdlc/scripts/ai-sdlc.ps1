[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("doctor", "dashboard", "new-task", "decompose", "queue", "executor", "submit-artifact", "handoff", "reopen-policy", "approval", "memory", "evidence", "pipeline", "orchestrator")]
    [string] $Command,
    [string] $Root = ".",
    [string] $TaskContractPath = "",
    [string] $Title = "",
    [string] $Task = "",
    [string] $FromRole = "",
    [string] $ToRole = "",
    [string] $Scope = "before_implementation",
    [string] $ChangedFile = "",
    [string] $ReportDirectory = "",
    [string] $Mode = "",
    [string] $Role = "",
    [string[]] $Set = @(),
    [string[]] $Append = @(),
    [string[]] $Artifact = @(),
    [switch] $Pretty,
    [switch] $NoOpen,
    [switch] $SkipValidationExecution,
    [switch] $SkipApprovalGates,
    [switch] $RequireExecutors
)

$ErrorActionPreference = "Stop"

function Invoke-AiSdlcScript {
    param(
        [string] $ScriptPath,
        [hashtable] $Parameters
    )

    $global:LASTEXITCODE = 0
    & $ScriptPath @Parameters
    $exitCode = $global:LASTEXITCODE
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        exit $exitCode
    }
}

switch ($Command) {
    "doctor" {
        $parameters = @{ Root = $Root }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/doctor-ai-sdlc.ps1" -Parameters $parameters
    }
    "dashboard" {
        $parameters = @{ Root = $Root }
        if ($NoOpen) { $parameters.NoOpen = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/start-ai-sdlc-dashboard.ps1" -Parameters $parameters
    }
    "new-task" {
        if (-not $Title) { throw "-Title is required for new-task." }
        $parameters = @{ Root = $Root; Title = $Title; EmitEvent = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/new-task-contract.ps1" -Parameters $parameters
    }
    "queue" {
        $parameters = @{ Root = $Root }
        if ($ReportDirectory) { $parameters.ReportDirectory = $ReportDirectory }
        if ($SkipApprovalGates) { $parameters.SkipApprovalGates = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/run-ai-sdlc-task-queue.ps1" -Parameters $parameters
    }
    "decompose" {
        if (-not $TaskContractPath) { throw "-TaskContractPath is required for decompose." }
        $parameters = @{ Root = $Root; TaskContractPath = $TaskContractPath; EmitEvent = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/write-task-decomposition.ps1" -Parameters $parameters
    }
    "executor" {
        $parameters = @{ Root = $Root }
        if ($ReportDirectory) { $parameters.ReportDirectory = $ReportDirectory }
        if ($Mode) { $parameters.Mode = $Mode }
        if ($SkipApprovalGates) { $parameters.SkipApprovalGates = $true }
        if ($RequireExecutors) { $parameters.RequireExecutors = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/run-ai-sdlc-executor.ps1" -Parameters $parameters
    }
    "submit-artifact" {
        if (-not $TaskContractPath -or -not $Role) { throw "-TaskContractPath and -Role are required for submit-artifact." }
        $parameters = @{ Root = $Root; TaskContractPath = $TaskContractPath; Role = $Role; Set = $Set; Append = $Append; Artifact = $Artifact }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/submit-role-artifact.ps1" -Parameters $parameters
    }
    "handoff" {
        if (-not $FromRole -or -not $ToRole -or -not $TaskContractPath) { throw "-FromRole, -ToRole, and -TaskContractPath are required for handoff." }
        $parameters = @{ Root = $Root; FromRole = $FromRole; ToRole = $ToRole; TaskContractPath = $TaskContractPath; EmitEvent = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/verify-handoff-gate.ps1" -Parameters $parameters
    }
    "reopen-policy" {
        $parameters = @{ Root = $Root }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/verify-reopen-policy.ps1" -Parameters $parameters
    }
    "approval" {
        if (-not $TaskContractPath) { throw "-TaskContractPath is required for approval." }
        $parameters = @{ Root = $Root; TaskContractPath = $TaskContractPath; Scope = $Scope; EmitEvent = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/verify-approval-gate.ps1" -Parameters $parameters
    }
    "memory" {
        $parameters = @{ Root = $Root }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/check-memory-lifecycle.ps1" -Parameters $parameters
    }
    "evidence" {
        $parameters = @{ Root = $Root }
        if ($ReportDirectory) { $parameters.ReportDirectory = $ReportDirectory }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/write-evidence-bundle.ps1" -Parameters $parameters
    }
    "pipeline" {
        $parameters = @{ Root = $Root }
        if ($ChangedFile) { $parameters.ChangedFile = @($ChangedFile) }
        if ($Task) { $parameters.Task = $Task }
        if ($SkipValidationExecution) { $parameters.SkipValidationExecution = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/run-ai-sdlc-pipeline.ps1" -Parameters $parameters
    }
    "orchestrator" {
        $parameters = @{ Root = $Root }
        if ($ChangedFile) { $parameters.ChangedFile = @($ChangedFile) }
        if ($Task) { $parameters.Task = $Task }
        if ($SkipValidationExecution) { $parameters.SkipValidationExecution = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        Invoke-AiSdlcScript -ScriptPath "$PSScriptRoot/run-ai-sdlc-orchestrator.ps1" -Parameters $parameters
    }
}
