[CmdletBinding()]
param(
    [string] $TargetRoot = ".",
    [string] $Profile = "generic",
    [switch] $Force
)

$ErrorActionPreference = "Stop"

function Resolve-FullPath {
    param([string] $Path)

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    return (Resolve-Path -LiteralPath $Path).Path
}

function Copy-FileIfAllowed {
    param(
        [string] $SourcePath,
        [string] $DestinationPath,
        [System.Collections.Generic.List[string]] $Copied,
        [System.Collections.Generic.List[string]] $Skipped
    )

    $destinationDirectory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory)) {
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    }

    if ((Test-Path -LiteralPath $DestinationPath) -and -not $Force) {
        $Skipped.Add($DestinationPath)
        return
    }

    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force:$Force
    $Copied.Add($DestinationPath)
}

function Copy-TreeIfAllowed {
    param(
        [string] $SourceRoot,
        [string] $DestinationRoot,
        [System.Collections.Generic.List[string]] $Copied,
        [System.Collections.Generic.List[string]] $Skipped
    )

    if (-not (Test-Path -LiteralPath $SourceRoot)) {
        throw "Missing export source directory: $SourceRoot"
    }

    Get-ChildItem -LiteralPath $SourceRoot -Recurse -File | ForEach-Object {
        $relative = $_.FullName.Substring($SourceRoot.Length).TrimStart("\", "/")
        $destination = Join-Path $DestinationRoot $relative
        Copy-FileIfAllowed -SourcePath $_.FullName -DestinationPath $destination -Copied $Copied -Skipped $Skipped
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$targetRootPath = Resolve-FullPath -Path $TargetRoot
$profilePath = Join-Path $scriptRoot "profiles\$Profile.yaml"

if (-not (Test-Path -LiteralPath $profilePath)) {
    $available = Get-ChildItem -LiteralPath (Join-Path $scriptRoot "profiles") -Filter "*.yaml" |
        ForEach-Object { $_.BaseName } |
        Sort-Object
    throw "Profile '$Profile' was not found. Available profiles: $($available -join ', ')"
}

$copied = [System.Collections.Generic.List[string]]::new()
$skipped = [System.Collections.Generic.List[string]]::new()

Copy-TreeIfAllowed `
    -SourceRoot (Join-Path $scriptRoot "docs") `
    -DestinationRoot (Join-Path $targetRootPath "docs") `
    -Copied $copied `
    -Skipped $skipped

Copy-TreeIfAllowed `
    -SourceRoot (Join-Path $scriptRoot "tools") `
    -DestinationRoot (Join-Path $targetRootPath "tools") `
    -Copied $copied `
    -Skipped $skipped

Copy-TreeIfAllowed `
    -SourceRoot (Join-Path $scriptRoot "dashboard") `
    -DestinationRoot (Join-Path $targetRootPath "dashboard") `
    -Copied $copied `
    -Skipped $skipped

Copy-TreeIfAllowed `
    -SourceRoot (Join-Path $scriptRoot "github") `
    -DestinationRoot (Join-Path $targetRootPath ".github") `
    -Copied $copied `
    -Skipped $skipped

Copy-FileIfAllowed `
    -SourcePath $profilePath `
    -DestinationPath (Join-Path $targetRootPath "tools\ai-sdlc\config\project-profile.yaml") `
    -Copied $copied `
    -Skipped $skipped

Copy-FileIfAllowed `
    -SourcePath (Join-Path $scriptRoot "AGENTS.md.template") `
    -DestinationPath (Join-Path $targetRootPath "AGENTS.md") `
    -Copied $copied `
    -Skipped $skipped

$summary = [ordered]@{
    targetRoot = $targetRootPath
    profile = $Profile
    copiedCount = $copied.Count
    skippedCount = $skipped.Count
    force = [bool]$Force
    nextSteps = @(
        "Edit tools/ai-sdlc/config/project-profile.yaml for the target repository.",
        "Edit tools/ai-sdlc/config/context_memory.yaml, integrations.yaml, and token_budget.yaml.",
        "Read AGENTS.md and docs/SDLC/README.md before starting AI-assisted work.",
        "Run tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.ps1 to generate fresh SDLC evidence.",
        "Run tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.ps1 -OpenDashboard to view live role progress.",
        "Review .github/workflows/ai-sdlc.yml before enabling strict project validation in CI.",
        "Do not copy old sdlc-*.json/md reports from another repository."
    )
}

$summary | ConvertTo-Json -Depth 5
