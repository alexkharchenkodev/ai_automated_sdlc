[CmdletBinding()]
param(
    [string] $Root = ".",
    [Parameter(Mandatory = $true)]
    [string] $FromRole,
    [Parameter(Mandatory = $true)]
    [string] $ToRole,
    [Parameter(Mandatory = $true)]
    [string] $TaskContractPath,
    [string] $ConfigPath = "",
    [string] $ReportDirectory = ".sdlc/handoffs",
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $EmitEvent,
    [switch] $NoExitCode,
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

$rootPath = Resolve-AiSdlcRoot -Root $Root
$config = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/handoff_gates.yaml" }
if (-not (Test-Path -LiteralPath $config)) { throw "Handoff gates config not found: $config" }

$contractFullPath = if ([System.IO.Path]::IsPathRooted($TaskContractPath)) { $TaskContractPath } else { Join-Path $rootPath $TaskContractPath }
if (-not (Test-Path -LiteralPath $contractFullPath)) { throw "Task contract not found: $contractFullPath" }
$contract = Get-Content -LiteralPath $contractFullPath -Raw | ConvertFrom-Json

$lines = (Get-Content -LiteralPath $config -Raw) -split "`r?`n"
$gates = Get-YamlNestedObjectMap -Lines $lines -RootKey "gates"
$selectedGate = $null
$selectedName = ""
foreach ($name in $gates.Keys) {
    $gate = $gates[$name]
    if ([string]$gate.from_role -eq $FromRole -and [string]$gate.to_role -eq $ToRole) {
        $selectedGate = $gate
        $selectedName = $name
        break
    }
}

$required = if ($selectedGate) { @($selectedGate.required_contract_fields) } else { @("taskId", "title", "acceptanceCriteria") }
$missing = [System.Collections.Generic.List[string]]::new()
foreach ($field in $required) {
    if (-not (Test-ContractValue -Object $contract -Path ([string]$field))) {
        $missing.Add([string]$field)
    }
}

$decision = if ($missing.Count -eq 0) { "proceed" } else { "reopen_required" }
$passed = $decision -eq "proceed"
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) { New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null }

$safeName = (($FromRole + "-to-" + $ToRole + "-" + $contract.taskId) -replace "[^A-Za-z0-9_.-]", "_")
$jsonPath = Join-Path $reportRoot "$safeName.json"
$mdPath = Join-Path $reportRoot "$safeName.md"
$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    gate = $selectedName
    fromRole = $FromRole
    toRole = $ToRole
    taskId = $contract.taskId
    taskTitle = $contract.title
    taskOrder = $contract.taskOrder
    passed = $passed
    decision = $decision
    requiredFields = @($required)
    missingFields = @($missing)
    taskContractPath = $contractFullPath
}
$mdLines = @(
    "- Decision: $decision",
    "- From: $FromRole",
    "- To: $ToRole",
    "- Task: $($contract.taskId)",
    "- Missing fields: $($missing.Count)"
)
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Handoff Gate" -Lines $mdLines

if ($EmitEvent) {
    if ($passed) {
        & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $contract.batchId -TaskId $contract.taskId -TaskTitle $contract.title -TaskOrder $contract.taskOrder -Role $ToRole -Status "running" -Message "Handoff gate passed from $FromRole to $ToRole." -Artifact @($jsonPath) -LiveDirectory $LiveDirectory | Out-Null
    } else {
        $reason = "Handoff gate $FromRole -> $ToRole missing: $(@($missing) -join ', ')"
        & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $contract.batchId -TaskId $contract.taskId -TaskTitle $contract.title -TaskOrder $contract.taskOrder -Role $ToRole -Status "revision_requested" -EventType "reopen" -ReopenToRole $FromRole -ReopenReason $reason -ReopenSeverity "warning" -Message $reason -Artifact @($jsonPath) -LiveDirectory $LiveDirectory | Out-Null
    }
}

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $jsonPath -Raw }
if (-not $passed -and -not $NoExitCode) { exit 2 }
