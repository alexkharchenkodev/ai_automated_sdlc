[CmdletBinding()]
param(
    [string] $Root = ".",
    [Parameter(Mandatory = $true)]
    [string] $Scope,
    [string] $Approver = "local-user",
    [string] $Status = "approved",
    [string] $Reason = "",
    [string] $OutputDirectory = ".sdlc/approvals",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$approvalRoot = if ([System.IO.Path]::IsPathRooted($OutputDirectory)) { $OutputDirectory } else { Join-Path $rootPath $OutputDirectory }
if (-not (Test-Path -LiteralPath $approvalRoot)) {
    New-Item -ItemType Directory -Force -Path $approvalRoot | Out-Null
}

$record = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    scope = $Scope
    approver = $Approver
    status = $Status
    reason = $Reason
}

$safeScope = ($Scope -replace "[^A-Za-z0-9_.-]", "_")
$path = Join-Path $approvalRoot ("approval-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss") + "-$safeScope.json")
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path

$result = [ordered]@{
    path = $path
    record = $record
}

if ($Pretty) { $result | ConvertTo-Json -Depth 8 } else { $path }
