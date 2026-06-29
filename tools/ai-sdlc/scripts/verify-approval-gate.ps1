[CmdletBinding()]
param(
    [string] $Root = ".",
    [Parameter(Mandatory = $true)]
    [string] $TaskContractPath,
    [string] $Scope = "before_implementation",
    [string] $ConfigPath = "",
    [string] $ReportDirectory = ".sdlc/approval-gates",
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $EmitEvent,
    [switch] $NoExitCode,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/approval_gates.yaml" }
if (-not (Test-Path -LiteralPath $config)) { throw "Approval gates config not found: $config" }

$settings = Get-YamlSectionScalarMap -Lines ((Get-Content -LiteralPath $config -Raw) -split "`r?`n") -RootKey "settings"
$approvalDir = if ($settings.approval_directory) { [string]$settings.approval_directory } else { ".sdlc/approvals" }
$requiredStatus = if ($settings.default_required_status) { [string]$settings.default_required_status } else { "approved" }

$contractFullPath = if ([System.IO.Path]::IsPathRooted($TaskContractPath)) { $TaskContractPath } else { Join-Path $rootPath $TaskContractPath }
if (-not (Test-Path -LiteralPath $contractFullPath)) { throw "Task contract not found: $contractFullPath" }
$contract = Get-Content -LiteralPath $contractFullPath -Raw | ConvertFrom-Json

$requiresApproval = @($contract.approvalsRequired) -contains $Scope
$approvalRoot = if ([System.IO.Path]::IsPathRooted($approvalDir)) { $approvalDir } else { Join-Path $rootPath $approvalDir }
$matchingRecords = @()
if (Test-Path -LiteralPath $approvalRoot) {
    $matchingRecords = @(Get-ChildItem -LiteralPath $approvalRoot -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
        try { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } catch { $null }
    } | Where-Object {
        $_ -and $_.scope -eq $Scope -and $_.status -eq $requiredStatus
    })
}

$passed = (-not $requiresApproval) -or $matchingRecords.Count -gt 0
$decision = if ($passed) { "proceed" } else { "waiting_for_approval" }

$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }
$safe = (($Scope + "-" + $contract.taskId) -replace "[^A-Za-z0-9_.-]", "_")
$jsonPath = Join-Path $reportRoot "sdlc-approval-gate-$safe.json"
$mdPath = Join-Path $reportRoot "sdlc-approval-gate-$safe.md"

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    taskId = $contract.taskId
    taskTitle = $contract.title
    scope = $Scope
    required = $requiresApproval
    passed = $passed
    decision = $decision
    requiredStatus = $requiredStatus
    approvalDirectory = $approvalRoot
    matchingApprovals = $matchingRecords.Count
}
$lines = @(
    "- Decision: $decision",
    "- Task: $($contract.taskId)",
    "- Scope: $Scope",
    "- Required: $requiresApproval",
    "- Matching approvals: $($matchingRecords.Count)"
)
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Approval Gate Report" -Lines $lines

if ($EmitEvent -and -not $passed) {
    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $contract.batchId -TaskId $contract.taskId -TaskTitle $contract.title -TaskOrder $contract.taskOrder -Role "engineering" -Status "waiting" -Message "Waiting for approval scope '$Scope'." -Artifact @($jsonPath) -LiveDirectory $LiveDirectory | Out-Null
}

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
if (-not $passed -and -not $NoExitCode) { exit 2 }
