[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("doctor", "dashboard", "new-task", "queue", "handoff", "reopen-policy", "approval", "memory", "evidence", "pipeline", "orchestrator")]
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
    [switch] $Pretty,
    [switch] $NoOpen,
    [switch] $SkipValidationExecution,
    [switch] $SkipApprovalGates
)

$ErrorActionPreference = "Stop"

switch ($Command) {
    "doctor" {
        $parameters = @{ Root = $Root }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/doctor-ai-sdlc.ps1" @parameters
    }
    "dashboard" {
        $parameters = @{ Root = $Root }
        if ($NoOpen) { $parameters.NoOpen = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/start-ai-sdlc-dashboard.ps1" @parameters
    }
    "new-task" {
        if (-not $Title) { throw "-Title is required for new-task." }
        $parameters = @{ Root = $Root; Title = $Title; EmitEvent = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/new-task-contract.ps1" @parameters
    }
    "queue" {
        $parameters = @{ Root = $Root }
        if ($ReportDirectory) { $parameters.ReportDirectory = $ReportDirectory }
        if ($SkipApprovalGates) { $parameters.SkipApprovalGates = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/run-ai-sdlc-task-queue.ps1" @parameters
    }
    "handoff" {
        if (-not $FromRole -or -not $ToRole -or -not $TaskContractPath) { throw "-FromRole, -ToRole, and -TaskContractPath are required for handoff." }
        $parameters = @{ Root = $Root; FromRole = $FromRole; ToRole = $ToRole; TaskContractPath = $TaskContractPath; EmitEvent = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/verify-handoff-gate.ps1" @parameters
    }
    "reopen-policy" {
        $parameters = @{ Root = $Root }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/verify-reopen-policy.ps1" @parameters
    }
    "approval" {
        if (-not $TaskContractPath) { throw "-TaskContractPath is required for approval." }
        $parameters = @{ Root = $Root; TaskContractPath = $TaskContractPath; Scope = $Scope; EmitEvent = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/verify-approval-gate.ps1" @parameters
    }
    "memory" {
        $parameters = @{ Root = $Root }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/check-memory-lifecycle.ps1" @parameters
    }
    "evidence" {
        $parameters = @{ Root = $Root }
        if ($ReportDirectory) { $parameters.ReportDirectory = $ReportDirectory }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/write-evidence-bundle.ps1" @parameters
    }
    "pipeline" {
        $parameters = @{ Root = $Root }
        if ($ChangedFile) { $parameters.ChangedFile = @($ChangedFile) }
        if ($Task) { $parameters.Task = $Task }
        if ($SkipValidationExecution) { $parameters.SkipValidationExecution = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/run-ai-sdlc-pipeline.ps1" @parameters
    }
    "orchestrator" {
        $parameters = @{ Root = $Root }
        if ($ChangedFile) { $parameters.ChangedFile = @($ChangedFile) }
        if ($Task) { $parameters.Task = $Task }
        if ($SkipValidationExecution) { $parameters.SkipValidationExecution = $true }
        if ($Pretty) { $parameters.Pretty = $true }
        & "$PSScriptRoot/run-ai-sdlc-orchestrator.ps1" @parameters
    }
}
