[CmdletBinding()]
param(
    [string] $TargetRoot = ".",
    [string] $SourceRoot = "",
    [switch] $ForceConfigs,
    [switch] $IncludeAgents,
    [switch] $IncludeGitHub,
    [switch] $DryRun
)

$ErrorActionPreference = "Stop"

function Resolve-ExistingPath {
    param([string] $Path, [string] $Label)
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Label not found: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path
}

function ConvertTo-SdlcPath {
    param([string] $Path)
    return (($Path -replace "\\", "/").TrimStart("/"))
}

function Copy-ManagedFile {
    param(
        [string] $SourcePath,
        [string] $DestinationPath,
        [string] $RelativePath,
        [bool] $Protected,
        [System.Collections.Generic.List[string]] $Updated,
        [System.Collections.Generic.List[string]] $StagedForReview,
        [System.Collections.Generic.List[string]] $Unchanged
    )

    $destinationDirectory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory) -and -not $DryRun) {
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    }

    $destinationExists = Test-Path -LiteralPath $DestinationPath
    $same = $false
    if ($destinationExists) {
        $sourceHash = (Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
        $destinationHash = (Get-FileHash -LiteralPath $DestinationPath -Algorithm SHA256).Hash
        $same = ($sourceHash -eq $destinationHash)
    }

    if ($same) {
        $Unchanged.Add($RelativePath)
        return
    }

    if ($Protected -and $destinationExists -and -not $ForceConfigs) {
        $reviewPath = "$DestinationPath.new"
        if (-not $DryRun) {
            Copy-Item -LiteralPath $SourcePath -Destination $reviewPath -Force
        }
        $StagedForReview.Add("$RelativePath.new")
        return
    }

    if (-not $DryRun) {
        Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
    }
    $Updated.Add($RelativePath)
}

function Update-InstallManifest {
    param(
        [string] $TargetRootPath,
        [string[]] $ManagedFiles,
        [string[]] $ProtectedFiles
    )

    $manifestPath = Join-Path $TargetRootPath ".sdlc/ai-sdlc-install-manifest.json"
    $manifestDirectory = Split-Path -Parent $manifestPath
    if (-not (Test-Path -LiteralPath $manifestDirectory)) {
        New-Item -ItemType Directory -Force -Path $manifestDirectory | Out-Null
    }

    $existing = @()
    if (Test-Path -LiteralPath $manifestPath) {
        $existingData = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $existing = @($existingData.managedFiles)
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        updatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        updater = "update-ai-sdlc.ps1"
        managedFiles = @(($existing + $ManagedFiles) | Where-Object { $_ } | Sort-Object -Unique)
        protectedUpdateFiles = @($ProtectedFiles)
        generatedDirectories = @(
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
    }

    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath
    return $manifestPath
}

$targetRootPath = Resolve-ExistingPath -Path $TargetRoot -Label "Target root"
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$sourceRootPath = if ($SourceRoot) { Resolve-ExistingPath -Path $SourceRoot -Label "Source root" } else { $scriptRoot }

foreach ($required in @("docs", "tools", "dashboard")) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRootPath $required))) {
        throw "Source root does not look like an AI SDLC framework checkout. Missing: $required"
    }
}

$protectedFiles = @(
    "AGENTS.md",
    "tools/ai-sdlc/config/project-profile.yaml",
    "tools/ai-sdlc/config/context_memory.yaml",
    "tools/ai-sdlc/config/integrations.yaml",
    "tools/ai-sdlc/config/token_budget.yaml",
    "tools/ai-sdlc/config/execution_lanes.yaml",
    "tools/ai-sdlc/config/mcp_servers.example.yaml"
)
$protectedSet = @{}
foreach ($file in $protectedFiles) { $protectedSet[$file] = $true }

$includeRoots = @(
    @{ source = "docs"; destination = "docs" },
    @{ source = "tools"; destination = "tools" },
    @{ source = "dashboard"; destination = "dashboard" },
    @{ source = "adapters"; destination = "adapters" }
)
if ($IncludeGitHub) {
    $includeRoots += @{ source = "github"; destination = ".github" }
}

$updated = [System.Collections.Generic.List[string]]::new()
$stagedForReview = [System.Collections.Generic.List[string]]::new()
$unchanged = [System.Collections.Generic.List[string]]::new()
$managed = [System.Collections.Generic.List[string]]::new()

foreach ($root in $includeRoots) {
    $sourceDirectory = Join-Path $sourceRootPath $root.source
    if (-not (Test-Path -LiteralPath $sourceDirectory)) {
        continue
    }

    Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File | ForEach-Object {
        $relativeInsideRoot = $_.FullName.Substring($sourceDirectory.Length).TrimStart("\", "/")
        $relative = ConvertTo-SdlcPath -Path (Join-Path $root.destination $relativeInsideRoot)
        $destination = Join-Path $targetRootPath $relative
        $isProtected = $protectedSet.ContainsKey($relative)
        Copy-ManagedFile -SourcePath $_.FullName -DestinationPath $destination -RelativePath $relative -Protected $isProtected -Updated $updated -StagedForReview $stagedForReview -Unchanged $unchanged
        if (-not $managed.Contains($relative)) { $managed.Add($relative) }
    }
}

if ($IncludeAgents) {
    $sourceAgents = Join-Path $sourceRootPath "AGENTS.md.template"
    if (Test-Path -LiteralPath $sourceAgents) {
        Copy-ManagedFile -SourcePath $sourceAgents -DestinationPath (Join-Path $targetRootPath "AGENTS.md") -RelativePath "AGENTS.md" -Protected $true -Updated $updated -StagedForReview $stagedForReview -Unchanged $unchanged
        if (-not $managed.Contains("AGENTS.md")) { $managed.Add("AGENTS.md") }
    }
}

$manifestPath = if ($DryRun) {
    Join-Path $targetRootPath ".sdlc/ai-sdlc-install-manifest.json"
} else {
    Update-InstallManifest -TargetRootPath $targetRootPath -ManagedFiles @($managed + $stagedForReview) -ProtectedFiles $protectedFiles
}

$result = [ordered]@{
    targetRoot = $targetRootPath
    sourceRoot = $sourceRootPath
    passed = $true
    dryRun = [bool]$DryRun
    forceConfigs = [bool]$ForceConfigs
    includeAgents = [bool]$IncludeAgents
    includeGitHub = [bool]$IncludeGitHub
    manifestPath = $manifestPath
    updatedCount = $updated.Count
    stagedForReviewCount = $stagedForReview.Count
    unchangedCount = $unchanged.Count
    updated = @($updated)
    stagedForReview = @($stagedForReview)
    unchanged = @($unchanged)
}

$result | ConvertTo-Json -Depth 8
