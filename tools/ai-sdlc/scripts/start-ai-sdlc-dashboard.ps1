[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $NoOpen,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$rootPath = Resolve-AiSdlcRoot -Root $Root
$liveRoot = Get-AiSdlcLiveDirectory -Root $rootPath -LiveDirectory $LiveDirectory
if (-not (Test-Path -LiteralPath $liveRoot)) {
    New-Item -ItemType Directory -Force -Path $liveRoot | Out-Null
}

$dashboardPath = Join-Path (Join-Path $liveRoot "dashboard") "index.html"
if (-not (Test-Path -LiteralPath $dashboardPath)) {
    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -RunId "system" -Role "system" -Status "pending" -Message "Dashboard initialized. Start an orchestrator run to see live role progress." -LiveDirectory $LiveDirectory | Out-Null
}

if (-not $NoOpen) {
    Start-Process -FilePath $dashboardPath | Out-Null
}

$result = [ordered]@{
    dashboardPath = $dashboardPath
    statePath = Join-Path $liveRoot "state.json"
    eventsPath = Join-Path $liveRoot "events.jsonl"
    opened = -not [bool]$NoOpen
}

if ($Pretty) {
    $result | ConvertTo-Json -Depth 8
} else {
    $result.dashboardPath
}
