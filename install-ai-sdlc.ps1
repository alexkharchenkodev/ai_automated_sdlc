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

function ConvertTo-RelativeSdlcPath {
    param(
        [string] $RootPath,
        [string] $Path
    )

    $normalizedRoot = $RootPath.TrimEnd("\", "/")
    if ($Path.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return ($Path.Substring($normalizedRoot.Length).TrimStart("\", "/") -replace "\\", "/")
    }

    return ($Path -replace "\\", "/")
}

function Write-InstallManifest {
    param(
        [string] $TargetRootPath,
        [string] $Profile,
        [System.Collections.Generic.List[string]] $Copied,
        [System.Collections.Generic.List[string]] $Skipped
    )

    $manifestPath = Join-Path $TargetRootPath ".sdlc/ai-sdlc-install-manifest.json"
    $manifestDirectory = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $manifestDirectory)) {
        New-Item -ItemType Directory -Force -Path $manifestDirectory | Out-Null
    }

    $managedFiles = @($Copied | ForEach-Object { ConvertTo-RelativeSdlcPath -RootPath $TargetRootPath -Path $_ } | Sort-Object -Unique)
    $skippedFiles = @($Skipped | ForEach-Object { ConvertTo-RelativeSdlcPath -RootPath $TargetRootPath -Path $_ } | Sort-Object -Unique)

    $manifest = [ordered]@{
        schemaVersion = 1
        installedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        installer = "install-ai-sdlc.ps1"
        profile = $Profile
        managedFiles = @($managedFiles)
        skippedFiles = @($skippedFiles)
        protectedUpdateFiles = @(
            "AGENTS.md",
            "tools/ai-sdlc/config/project-profile.yaml",
            "tools/ai-sdlc/config/context_memory.yaml",
            "tools/ai-sdlc/config/integrations.yaml",
            "tools/ai-sdlc/config/token_budget.yaml",
            "tools/ai-sdlc/config/execution_lanes.yaml",
            "tools/ai-sdlc/config/mcp_servers.example.yaml"
        )
        generatedDirectories = @(
            ".sdlc/local-pipeline",
            ".sdlc/live",
            ".sdlc/approvals"
        )
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath
    return $manifestPath
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

$manifestPath = Write-InstallManifest -TargetRootPath $targetRootPath -Profile $Profile -Copied $copied -Skipped $skipped

$summary = [ordered]@{
    targetRoot = $targetRootPath
    profile = $Profile
    copiedCount = $copied.Count
    skippedCount = $skipped.Count
    manifestPath = $manifestPath
    force = [bool]$Force
    nextSteps = @(
        "Edit tools/ai-sdlc/config/project-profile.yaml for the target repository.",
        "Edit tools/ai-sdlc/config/context_memory.yaml, integrations.yaml, token_budget.yaml, and execution_lanes.yaml.",
        "Read AGENTS.md and docs/SDLC/README.md before starting AI-assisted work.",
        "Run tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.ps1 to generate fresh SDLC evidence.",
        "Run tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.ps1 -OpenDashboard to view live role progress.",
        "Use update-ai-sdlc.ps1 from a newer framework checkout to update this AI SDLC baseline.",
        "Use uninstall-ai-sdlc.ps1 with -DryRun first if you need to remove this AI SDLC baseline later.",
        "Review .github/workflows/ai-sdlc.yml before enabling strict project validation in CI.",
        "Do not copy old sdlc-*.json/md reports from another repository."
    )
}

$summary | ConvertTo-Json -Depth 5
