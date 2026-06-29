[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ConfigPath = "",
    [string] $OutputPath = ""
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

$profile = Read-AiSdlcProfile -Root $Root -ConfigPath $ConfigPath
$json = $profile | ConvertTo-Json -Depth 12

if ($OutputPath) {
    $directory = Split-Path -Parent $OutputPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }
    Set-Content -LiteralPath $OutputPath -Value $json
}

$json
