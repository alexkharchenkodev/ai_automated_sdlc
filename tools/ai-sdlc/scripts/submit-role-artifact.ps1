[CmdletBinding()]
param(
    [string] $Root = ".",
    [Parameter(Mandatory = $true)]
    [string] $TaskContractPath,
    [Parameter(Mandatory = $true)]
    [string] $Role,
    [string[]] $Set = @(),
    [string[]] $Append = @(),
    [string[]] $Artifact = @(),
    [string] $Status = "completed",
    [string] $Message = "",
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Split-Assignment {
    param([string] $Assignment)

    $index = $Assignment.IndexOf("=")
    if ($index -lt 1) {
        throw "Expected assignment in the form field=value. Got: $Assignment"
    }

    return [ordered]@{
        key = $Assignment.Substring(0, $index).Trim()
        value = $Assignment.Substring($index + 1).Trim()
    }
}

function Expand-AssignmentList {
    param([string[]] $Assignments)

    $expanded = [System.Collections.Generic.List[string]]::new()
    foreach ($assignment in @($Assignments)) {
        if ([string]::IsNullOrWhiteSpace($assignment)) { continue }
        $parts = [regex]::Split($assignment, "[;,](?=[A-Za-z0-9_.-]+=)")
        foreach ($part in $parts) {
            if (-not [string]::IsNullOrWhiteSpace($part)) {
                $expanded.Add($part.Trim())
            }
        }
    }

    return @($expanded)
}

function Set-ContractField {
    param(
        [object] $Contract,
        [string] $Name,
        [object] $Value,
        [bool] $AppendValue
    )

    $property = $Contract.PSObject.Properties[$Name]
    if ($AppendValue) {
        $existing = if ($property) { @($property.Value) } else { @() }
        $updated = @($existing + $Value | Where-Object { $_ -ne $null -and "$_".Trim() })
        if ($property) {
            $property.Value = @($updated)
        } else {
            $Contract | Add-Member -NotePropertyName $Name -NotePropertyValue @($updated) -Force
        }
        return
    }

    if ($property) {
        $property.Value = @($Value)
    } else {
        $Contract | Add-Member -NotePropertyName $Name -NotePropertyValue @($Value) -Force
    }
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$contractPath = if ([System.IO.Path]::IsPathRooted($TaskContractPath)) { $TaskContractPath } else { Join-Path $rootPath $TaskContractPath }
if (-not (Test-Path -LiteralPath $contractPath)) { throw "Task contract not found: $contractPath" }

$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
$expandedSet = Expand-AssignmentList -Assignments $Set
$expandedAppend = Expand-AssignmentList -Assignments $Append

foreach ($assignment in @($expandedSet)) {
    $pair = Split-Assignment -Assignment $assignment
    Set-ContractField -Contract $contract -Name $pair.key -Value $pair.value -AppendValue $false
}

foreach ($assignment in @($expandedAppend)) {
    $pair = Split-Assignment -Assignment $assignment
    Set-ContractField -Contract $contract -Name $pair.key -Value $pair.value -AppendValue $true
}

if (@($Artifact).Count -gt 0) {
    Set-ContractField -Contract $contract -Name "artifacts" -Value @($Artifact) -AppendValue $true
}

$contract | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $contractPath

$eventMessage = if ($Message) { $Message } else { "Role artifact submitted for $Role." }
& "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -BatchId $contract.batchId -TaskId $contract.taskId -TaskTitle $contract.title -TaskOrder $contract.taskOrder -Role $Role -Status $Status -Message $eventMessage -Artifact @($Artifact + $contractPath) -LiveDirectory $LiveDirectory | Out-Null

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    taskId = $contract.taskId
    role = $Role
    status = $Status
    contractPath = $contractPath
    setCount = @($expandedSet).Count
    appendCount = @($expandedAppend).Count
    artifacts = @($Artifact)
}

if ($Pretty) { $result | ConvertTo-Json -Depth 12 } else { $result.contractPath }
