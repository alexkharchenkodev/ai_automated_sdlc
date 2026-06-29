[CmdletBinding()]
param(
    [string] $TargetRoot = ".",
    [string] $ManifestPath = "",
    [switch] $IncludeGenerated,
    [switch] $ForceFallback,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-TargetRoot {
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Target root not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function ConvertTo-SdlcPath {
    param([string] $Path)
    return (($Path -replace "\\", "/").TrimStart("/"))
}

function Get-FallbackManagedFiles {
    param([string] $RootPath)

    $files = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in @("docs/SDLC", "docs/LLM", "tools/ai-sdlc", "dashboard", "adapters")) {
        $full = Join-Path $RootPath $dir
        if (Test-Path -LiteralPath $full) {
            Get-ChildItem -LiteralPath $full -Recurse -File | ForEach-Object {
                $relative = $_.FullName.Substring($RootPath.Length).TrimStart("\", "/") -replace "\\", "/"
                $files.Add($relative)
            }
        }
    }

    foreach ($file in @(".github/PULL_REQUEST_TEMPLATE.md", ".github/workflows/ai-sdlc.yml", "AGENTS.md")) {
        if (Test-Path -LiteralPath (Join-Path $RootPath $file)) {
            $files.Add($file)
        }
    }

    return @($files | Sort-Object -Unique)
}

function Remove-FileIfPresent {
    param(
        [string] $RootPath,
        [string] $RelativePath,
        [System.Collections.Generic.List[string]] $Removed,
        [System.Collections.Generic.List[string]] $Missing
    )

    $normalized = ConvertTo-SdlcPath -Path $RelativePath
    $path = Join-Path $RootPath $normalized
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        if (-not $DryRun) {
            Remove-Item -LiteralPath $path -Force
        }
        $Removed.Add($normalized)
    } else {
        $Missing.Add($normalized)
    }
}

function Remove-GeneratedDirectory {
    param(
        [string] $RootPath,
        [string] $RelativePath,
        [System.Collections.Generic.List[string]] $Removed
    )

    $path = Join-Path $RootPath $RelativePath
    if (Test-Path -LiteralPath $path) {
        if (-not $DryRun) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
        $Removed.Add($RelativePath)
    }
}

function Remove-EmptyDirectories {
    param([string] $RootPath)

    foreach ($relative in @(
        "dashboard",
        "adapters/codex",
        "adapters/copilot",
        "adapters/claude",
        "adapters/cursor",
        "adapters/generic",
        "adapters",
        "tools/ai-sdlc/scripts",
        "tools/ai-sdlc/config",
        "tools/ai-sdlc",
        "tools",
        "docs/SDLC/templates",
        "docs/SDLC",
        "docs/LLM",
        ".github/workflows",
        ".github",
        ".sdlc"
    )) {
        $path = Join-Path $RootPath $relative
        if (Test-Path -LiteralPath $path -PathType Container) {
            $hasChildren = @(Get-ChildItem -LiteralPath $path -Force).Count -gt 0
            if (-not $hasChildren -and -not $DryRun) {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }
}

$rootPath = Resolve-TargetRoot -Path $TargetRoot
$manifest = if ($ManifestPath) { $ManifestPath } else { Join-Path $rootPath ".sdlc/ai-sdlc-install-manifest.json" }
$usedFallback = $false

if (Test-Path -LiteralPath $manifest) {
    $manifestData = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
    $managedFiles = @($manifestData.managedFiles)
    $generatedDirectories = @($manifestData.generatedDirectories)
} elseif ($ForceFallback) {
    $usedFallback = $true
    $managedFiles = @(Get-FallbackManagedFiles -RootPath $rootPath)
    $generatedDirectories = @(
        ".sdlc/local-pipeline",
        ".sdlc/live",
        ".sdlc/approvals",
        ".sdlc/task-contracts",
        ".sdlc/task-queue",
        ".sdlc/handoffs",
        ".sdlc/reopen-policy",
        ".sdlc/approval-gates",
        ".sdlc/memory-index",
        ".sdlc/memory-lifecycle"
    )
} else {
    $result = [ordered]@{
        targetRoot = $rootPath
        passed = $false
        dryRun = [bool]$DryRun
        message = "Install manifest not found. Re-run with -ForceFallback to remove the standard AI SDLC paths."
        manifestPath = $manifest
    }
    $result | ConvertTo-Json -Depth 6
    exit 2
}

$removed = [System.Collections.Generic.List[string]]::new()
$missing = [System.Collections.Generic.List[string]]::new()
foreach ($relative in $managedFiles) {
    Remove-FileIfPresent -RootPath $rootPath -RelativePath $relative -Removed $removed -Missing $missing
}

$removedGenerated = [System.Collections.Generic.List[string]]::new()
if ($IncludeGenerated) {
    foreach ($relative in $generatedDirectories) {
        Remove-GeneratedDirectory -RootPath $rootPath -RelativePath $relative -Removed $removedGenerated
    }
}

if (Test-Path -LiteralPath $manifest) {
    if (-not $DryRun) {
        Remove-Item -LiteralPath $manifest -Force
    }
    $removed.Add((ConvertTo-SdlcPath -Path ($manifest.Substring($rootPath.Length).TrimStart("\", "/"))))
}

Remove-EmptyDirectories -RootPath $rootPath

$result = [ordered]@{
    targetRoot = $rootPath
    passed = $true
    dryRun = [bool]$DryRun
    includeGenerated = [bool]$IncludeGenerated
    usedFallback = $usedFallback
    removedCount = $removed.Count
    missingCount = $missing.Count
    removedGeneratedDirectories = @($removedGenerated)
    removed = @($removed)
    missing = @($missing)
}

$result | ConvertTo-Json -Depth 8
