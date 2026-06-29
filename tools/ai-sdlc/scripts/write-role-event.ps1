[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $RunId = "",
    [Parameter(Mandatory = $true)]
    [string] $Role,
    [Parameter(Mandatory = $true)]
    [ValidateSet("pending", "running", "completed", "skipped", "blocked", "failed", "waiting")]
    [string] $Status,
    [string] $Message = "",
    [string[]] $Artifact = @(),
    [string] $LiveDirectory = ".sdlc/live",
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function ConvertTo-HtmlText {
    param([string] $Value)
    return [System.Net.WebUtility]::HtmlEncode($Value)
}

function ConvertTo-JsAssignment {
    param(
        [string] $GlobalName,
        [object] $Value
    )

    $json = if ($null -eq $Value) { "null" } else { $Value | ConvertTo-Json -Depth 20 -Compress }
    return "window.$GlobalName = $json;"
}

function Read-DashboardConfigFile {
    param(
        [string] $RootPath,
        [string] $RelativePath
    )

    $path = Join-Path $RootPath $RelativePath
    $present = Test-Path -LiteralPath $path
    return [pscustomobject]@{
        name = [System.IO.Path]::GetFileName($RelativePath)
        relativePath = $RelativePath
        path = $path
        present = $present
        sizeBytes = if ($present) { (Get-Item -LiteralPath $path).Length } else { 0 }
    }
}

function Test-AiSdlcPathUnderRoot {
    param(
        [string] $RootPath,
        [string] $CandidatePath
    )

    if (-not $CandidatePath) { return $false }
    $rootFull = [System.IO.Path]::GetFullPath($RootPath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $candidateFull = [System.IO.Path]::GetFullPath($CandidatePath).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    return ($candidateFull -eq $rootFull -or $candidateFull.StartsWith($rootFull + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase))
}

function Read-AiSdlcTextPreview {
    param(
        [string] $Path,
        [int] $MaxChars
    )

    $reader = $null
    try {
        $reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8, $true)
        $buffer = New-Object char[] ($MaxChars + 1)
        $read = $reader.Read($buffer, 0, $buffer.Length)
        if ($read -le 0) {
            return [pscustomobject]@{ content = ""; truncated = $false }
        }

        $take = [Math]::Min($read, $MaxChars)
        $content = -join $buffer[0..($take - 1)]
        return [pscustomobject]@{
            content = $content
            truncated = ($read -gt $MaxChars)
        }
    } finally {
        if ($reader) { $reader.Dispose() }
    }
}

function Get-AiSdlcMemoryPreviewFiles {
    param(
        [string] $DirectoryPath,
        [int] $MaxFiles
    )

    $allowedExtensions = @(".md", ".txt", ".json", ".yaml", ".yml", ".toml", ".xml", ".cs", ".ts", ".tsx", ".js", ".jsx", ".html", ".css", ".scss", ".py", ".swift", ".kt", ".java", ".go", ".rs", ".sql")
    $excludedSegments = @("\.git\", "\node_modules\", "\bin\", "\obj\", "\.sdlc\live\", "\.sdlc\tmp\")
    return @(Get-ChildItem -LiteralPath $DirectoryPath -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $path = $_.FullName
            $allowedExtensions -contains $_.Extension.ToLowerInvariant() -and
            -not ($excludedSegments | Where-Object { $path.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
        } |
        Sort-Object FullName |
        Select-Object -First $MaxFiles)
}

function Read-AiSdlcMemorySourcePreview {
    param(
        [string] $RootPath,
        [object] $Source,
        [int] $MaxCharsPerSource,
        [int] $MaxFilesPerDirectory
    )

    $sourcePath = [string]$Source.path
    $resolvedPath = [string]$Source.resolvedPath
    $status = [string]$Source.status

    $base = [ordered]@{
        path = $sourcePath
        resolvedPath = $resolvedPath
        status = $status
        type = "unavailable"
        sizeBytes = 0
        truncated = $false
        content = ""
    }

    if ($status -ne "available" -or -not $resolvedPath -or -not (Test-Path -LiteralPath $resolvedPath)) {
        return [pscustomobject]$base
    }

    if (-not (Test-AiSdlcPathUnderRoot -RootPath $RootPath -CandidatePath $resolvedPath)) {
        $base["status"] = "outside_project_root"
        return [pscustomobject]$base
    }

    $item = Get-Item -LiteralPath $resolvedPath -ErrorAction SilentlyContinue
    if (-not $item) {
        $base["status"] = "missing"
        return [pscustomobject]$base
    }

    if ($item.PSIsContainer) {
        $base["type"] = "directory"
        $files = Get-AiSdlcMemoryPreviewFiles -DirectoryPath $resolvedPath -MaxFiles $MaxFilesPerDirectory
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add("Directory preview: $sourcePath")
        $lines.Add("Included files: $($files.Count)")
        $lines.Add("")
        $usedChars = 0
        $sizeBytes = 0
        $truncated = $false

        foreach ($file in $files) {
            $relative = $file.FullName.Substring(([System.IO.Path]::GetFullPath($RootPath)).Length).TrimStart("\", "/")
            $remaining = $MaxCharsPerSource - $usedChars
            if ($remaining -le 0) {
                $truncated = $true
                break
            }

            $perFileLimit = [Math]::Min(1800, $remaining)
            $snippet = Read-AiSdlcTextPreview -Path $file.FullName -MaxChars $perFileLimit
            $entry = @"
--- $relative
$($snippet.content)
"@
            $lines.Add($entry.TrimEnd())
            $lines.Add("")
            $usedChars += $entry.Length
            $sizeBytes += $file.Length
            if ($snippet.truncated) { $truncated = $true }
        }

        $base["sizeBytes"] = $sizeBytes
        $base["truncated"] = $truncated
        $base["content"] = ($lines -join [Environment]::NewLine).TrimEnd()
        return [pscustomobject]$base
    }

    $base["type"] = "file"
    $preview = Read-AiSdlcTextPreview -Path $resolvedPath -MaxChars $MaxCharsPerSource
    $base["sizeBytes"] = $item.Length
    $base["truncated"] = $preview.truncated
    $base["content"] = $preview.content
    return [pscustomobject]$base
}

function Read-AiSdlcMemoryContent {
    param(
        [string] $RootPath,
        [object] $ContextMemory,
        [int] $MaxCharsPerSource = 12000,
        [int] $MaxFilesPerDirectory = 24
    )

    if ($null -eq $ContextMemory -or -not $ContextMemory.providers) {
        return $null
    }

    $providerPreviews = [System.Collections.Generic.List[object]]::new()
    foreach ($provider in @($ContextMemory.providers)) {
        $sourcePreviews = [System.Collections.Generic.List[object]]::new()
        foreach ($source in @($provider.sources)) {
            $sourcePreviews.Add((Read-AiSdlcMemorySourcePreview -RootPath $RootPath -Source $source -MaxCharsPerSource $MaxCharsPerSource -MaxFilesPerDirectory $MaxFilesPerDirectory))
        }

        $providerPreviews.Add([ordered]@{
            name = $provider.name
            enabled = $provider.enabled
            mode = $provider.mode
            sources = @($sourcePreviews)
        })
    }

    return [ordered]@{
        schemaVersion = 1
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        maxCharsPerSource = $MaxCharsPerSource
        maxFilesPerDirectory = $MaxFilesPerDirectory
        providers = @($providerPreviews)
    }
}

function New-DashboardHtml {
    param(
        [object] $State,
        [object[]] $Events
    )

    $roleCards = [System.Collections.Generic.List[string]]::new()
    foreach ($role in @($State.roles)) {
        $status = if ($role.status) { $role.status } else { "pending" }
        $activeClass = if ($role.id -eq $State.activeRole) { " active" } else { "" }
        $artifactHtml = ""
        foreach ($artifact in @($role.artifacts)) {
            $artifactHtml += "<li>$(ConvertTo-HtmlText -Value ([string]$artifact))</li>"
        }
        if (-not $artifactHtml) { $artifactHtml = "<li class=`"muted`">No artifacts yet</li>" }
        $roleCards.Add(@"
<section class="role-card status-$status$activeClass">
  <div class="role-top">
    <span class="role-title">$(ConvertTo-HtmlText -Value ([string]$role.title))</span>
    <span class="badge">$status</span>
  </div>
  <p>$(ConvertTo-HtmlText -Value ([string]$role.purpose))</p>
  <p class="message">$(ConvertTo-HtmlText -Value ([string]$role.message))</p>
  <ul>$artifactHtml</ul>
</section>
"@)
    }

    $eventRows = [System.Collections.Generic.List[string]]::new()
    foreach ($event in @($Events | Select-Object -Last 80)) {
        $artifactText = (@($event.artifacts) -join ", ")
        $eventRows.Add("<tr><td>$(ConvertTo-HtmlText -Value ([string]$event.timeUtc))</td><td>$(ConvertTo-HtmlText -Value ([string]$event.role))</td><td><span class=`"badge small status-$($event.status)`">$(ConvertTo-HtmlText -Value ([string]$event.status))</span></td><td>$(ConvertTo-HtmlText -Value ([string]$event.message))</td><td>$(ConvertTo-HtmlText -Value $artifactText)</td></tr>")
    }

    $generated = ConvertTo-HtmlText -Value ([string]$State.updatedAtUtc)
    $active = ConvertTo-HtmlText -Value ([string]$State.activeRole)
    $decision = ConvertTo-HtmlText -Value ([string]$State.decision)
    $runId = ConvertTo-HtmlText -Value ([string]$State.runId)

    return @"
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>AI SDLC Live Dashboard</title>
  <style>
    :root { color-scheme: light; --bg:#f7f8fb; --panel:#ffffff; --text:#172033; --muted:#687386; --line:#d9dfeb; --run:#2764d8; --ok:#16845b; --warn:#aa6500; --bad:#b42318; --wait:#6f42c1; }
    * { box-sizing: border-box; }
    body { margin: 0; font-family: Inter, Segoe UI, Arial, sans-serif; background: var(--bg); color: var(--text); }
    header { padding: 24px 32px 16px; background: var(--panel); border-bottom: 1px solid var(--line); position: sticky; top: 0; z-index: 2; }
    h1 { margin: 0 0 8px; font-size: 24px; }
    .meta { display: flex; flex-wrap: wrap; gap: 12px; color: var(--muted); font-size: 13px; }
    main { padding: 24px 32px 40px; max-width: 1400px; margin: 0 auto; }
    .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 14px; }
    .role-card { background: var(--panel); border: 1px solid var(--line); border-left: 5px solid #9aa5b8; border-radius: 8px; padding: 14px; min-height: 176px; }
    .role-card.active { box-shadow: 0 8px 24px rgba(39, 100, 216, .16); transform: translateY(-1px); }
    .role-top { display:flex; align-items:center; justify-content:space-between; gap: 12px; }
    .role-title { font-weight: 700; }
    .role-card p { margin: 8px 0; color: var(--muted); line-height: 1.35; }
    .role-card .message { color: var(--text); min-height: 36px; }
    ul { margin: 8px 0 0; padding-left: 18px; color: var(--muted); }
    .badge { display:inline-flex; align-items:center; border-radius: 999px; padding: 4px 9px; background:#eef2f8; color:#263347; font-size: 12px; font-weight: 700; text-transform: uppercase; letter-spacing: .02em; }
    .small { font-size: 11px; padding: 3px 7px; }
    .status-running { border-left-color: var(--run); }
    .status-completed { border-left-color: var(--ok); }
    .status-skipped, .status-waiting { border-left-color: var(--wait); }
    .status-blocked, .status-failed { border-left-color: var(--bad); }
    .status-running.badge, .badge.status-running { background:#e9f0ff; color:var(--run); }
    .status-completed.badge, .badge.status-completed { background:#e9f8f2; color:var(--ok); }
    .status-skipped.badge, .status-waiting.badge, .badge.status-skipped, .badge.status-waiting { background:#f4edff; color:var(--wait); }
    .status-blocked.badge, .status-failed.badge, .badge.status-blocked, .badge.status-failed { background:#fff0ee; color:var(--bad); }
    h2 { margin: 32px 0 12px; font-size: 18px; }
    table { width: 100%; border-collapse: collapse; background: var(--panel); border: 1px solid var(--line); border-radius: 8px; overflow: hidden; }
    th, td { padding: 10px 12px; border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; font-size: 13px; }
    th { background:#eef2f8; color:#364259; }
    .muted { color: var(--muted); }
  </style>
</head>
<body>
  <header>
    <h1>AI SDLC Live Dashboard</h1>
    <div class="meta">
      <span>Run: $runId</span>
      <span>Active role: $active</span>
      <span>Decision: $decision</span>
      <span>Updated: $generated</span>
      <span>Static fallback dashboard</span>
    </div>
  </header>
  <main>
    <section class="grid">
      $($roleCards -join "`n")
    </section>
    <h2>Event Log</h2>
    <table>
      <thead><tr><th>Time UTC</th><th>Role</th><th>Status</th><th>Message</th><th>Artifacts</th></tr></thead>
      <tbody>
        $($eventRows -join "`n")
      </tbody>
    </table>
  </main>
</body>
</html>
"@
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$liveRoot = Get-AiSdlcLiveDirectory -Root $rootPath -LiveDirectory $LiveDirectory
if (-not (Test-Path -LiteralPath $liveRoot)) {
    New-Item -ItemType Directory -Force -Path $liveRoot | Out-Null
}

if (-not $RunId) {
    $RunId = "local"
}

$eventsPath = Join-Path $liveRoot "events.jsonl"
$statePath = Join-Path $liveRoot "state.json"
$dashboardRoot = Join-Path $liveRoot "dashboard"
$htmlPath = Join-Path $dashboardRoot "index.html"
$runtimeStatePath = Join-Path $dashboardRoot "runtime-state.js"

if (-not (Test-Path -LiteralPath $dashboardRoot)) {
    New-Item -ItemType Directory -Force -Path $dashboardRoot | Out-Null
}

$dashboardSource = Join-Path $rootPath "dashboard"
if (Test-Path -LiteralPath $dashboardSource) {
    Copy-Item -LiteralPath (Join-Path $dashboardSource "index.html") -Destination (Join-Path $dashboardRoot "index.html") -Force
    Copy-Item -LiteralPath (Join-Path $dashboardSource "styles.css") -Destination (Join-Path $dashboardRoot "styles.css") -Force
    Copy-Item -LiteralPath (Join-Path $dashboardSource "app.js") -Destination (Join-Path $dashboardRoot "app.js") -Force
}

$event = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    timeUtc = (Get-Date).ToUniversalTime().ToString("o")
    role = $Role
    status = $Status
    message = $Message
    artifacts = @($Artifact)
}

$eventLine = ($event | ConvertTo-Json -Depth 8 -Compress)
[System.IO.File]::AppendAllText($eventsPath, $eventLine + [Environment]::NewLine, [System.Text.Encoding]::UTF8)

$roleFlow = Get-AiSdlcRoleFlow -Root $rootPath
$events = [System.Collections.Generic.List[object]]::new()
if (Test-Path -LiteralPath $eventsPath) {
    foreach ($line in Get-Content -LiteralPath $eventsPath) {
        if ($line.Trim()) {
            $events.Add(($line | ConvertFrom-Json))
        }
    }
}

$roles = [System.Collections.Generic.List[object]]::new()
foreach ($roleDef in @($roleFlow)) {
    $roleEvents = @($events | Where-Object { $_.role -eq $roleDef.id })
    $latest = $roleEvents | Select-Object -Last 1
    $artifacts = [System.Collections.Generic.List[string]]::new()
    foreach ($roleEvent in $roleEvents) {
        foreach ($artifact in @($roleEvent.artifacts)) {
            if ($artifact -and -not $artifacts.Contains([string]$artifact)) {
                $artifacts.Add([string]$artifact)
            }
        }
    }

    $roles.Add([ordered]@{
        id = $roleDef.id
        title = if ($roleDef.title) { $roleDef.title } else { $roleDef.id }
        purpose = $roleDef.purpose
        status = if ($latest) { $latest.status } else { "pending" }
        message = if ($latest) { $latest.message } else { "" }
        updatedAtUtc = if ($latest) { $latest.timeUtc } else { "" }
        artifacts = @($artifacts)
    })
}

$blocking = @($roles | Where-Object { $_.status -eq "blocked" -or $_.status -eq "failed" })
$running = @($roles | Where-Object { $_.status -eq "running" }) | Select-Object -First 1
$waiting = @($roles | Where-Object { $_.status -eq "waiting" }) | Select-Object -First 1
$done = @($roles | Where-Object { $_.id -eq "done" -and $_.status -eq "completed" }) | Select-Object -First 1
$activeRole = if ($running) { $running.id } elseif ($waiting) { $waiting.id } elseif ($done) { "done" } else { $Role }
$decision = if ($blocking.Count -gt 0) { "blocked" } elseif (@($roles | Where-Object { $_.status -eq "running" }).Count -gt 0) { "running" } elseif ($waiting) { "waiting" } elseif ($done) { "proceed" } else { "review" }

$state = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    updatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    activeRole = $activeRole
    decision = $decision
    project = (Read-AiSdlcProfile -Root $rootPath)
    liveDirectory = $liveRoot
    eventsPath = $eventsPath
    dashboardPath = $htmlPath
    roles = @($roles)
}

$state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath

$reportRoot = Join-Path $rootPath ".sdlc/local-pipeline"
$summaryPath = Join-Path $reportRoot "sdlc-summary.json"
$doctorPath = Join-Path $rootPath ".sdlc/doctor/sdlc-doctor-report.json"
$lanePath = Join-Path $reportRoot "sdlc-lane-report.json"
$safeChangePath = Join-Path $reportRoot "sdlc-safe-change-report.json"
$compliancePath = Join-Path $reportRoot "sdlc-compliance-report.json"
$contextPath = Join-Path $reportRoot "sdlc-context-memory-report.json"
$integrationsPath = Join-Path $reportRoot "sdlc-integrations-report.json"
$tokenPath = Join-Path $reportRoot "sdlc-token-usage-report.json"
$summary = if (Test-Path -LiteralPath $summaryPath) { Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json } else { $null }
$doctor = if (Test-Path -LiteralPath $doctorPath) { Get-Content -LiteralPath $doctorPath -Raw | ConvertFrom-Json } else { $null }
$lane = if (Test-Path -LiteralPath $lanePath) { Get-Content -LiteralPath $lanePath -Raw | ConvertFrom-Json } else { $null }
$safeChange = if (Test-Path -LiteralPath $safeChangePath) { Get-Content -LiteralPath $safeChangePath -Raw | ConvertFrom-Json } else { $null }
$compliance = if (Test-Path -LiteralPath $compliancePath) { Get-Content -LiteralPath $compliancePath -Raw | ConvertFrom-Json } else { $null }
$contextMemory = if (Test-Path -LiteralPath $contextPath) { Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json } else { $null }
$integrations = if (Test-Path -LiteralPath $integrationsPath) { Get-Content -LiteralPath $integrationsPath -Raw | ConvertFrom-Json } else { $null }
$tokenUsage = if (Test-Path -LiteralPath $tokenPath) { Get-Content -LiteralPath $tokenPath -Raw | ConvertFrom-Json } else { $null }
$memoryContent = Read-AiSdlcMemoryContent -RootPath $rootPath -ContextMemory $contextMemory
$dashboardConfigFiles = @(
    "tools/ai-sdlc/config/project-profile.yaml",
    "tools/ai-sdlc/config/context_memory.yaml",
    "tools/ai-sdlc/config/integrations.yaml",
    "tools/ai-sdlc/config/token_budget.yaml",
    "tools/ai-sdlc/config/role_flow.yaml",
    "tools/ai-sdlc/config/safety_gates.yaml",
    "tools/ai-sdlc/config/execution_lanes.yaml"
)
$dashboardConfig = [pscustomobject]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    files = [object[]]@($dashboardConfigFiles | ForEach-Object { Read-DashboardConfigFile -RootPath $rootPath -RelativePath $_ })
}

$runtimeLines = [System.Collections.Generic.List[string]]::new()
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_STATE" -Value $state))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_EVENTS" -Value @($events)))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_SUMMARY" -Value $summary))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_DOCTOR" -Value $doctor))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_LANE" -Value $lane))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_SAFETY" -Value $safeChange))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_COMPLIANCE" -Value $compliance))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_CONTEXT_MEMORY" -Value $contextMemory))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_MEMORY_CONTENT" -Value $memoryContent))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_INTEGRATIONS" -Value $integrations))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_TOKEN_USAGE" -Value $tokenUsage))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_CONFIG" -Value $dashboardConfig))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_PROFILE" -Value $state.project))
Set-Content -LiteralPath $runtimeStatePath -Value $runtimeLines

$result = [ordered]@{
    event = $event
    statePath = $statePath
    dashboardPath = $htmlPath
    runtimeStatePath = $runtimeStatePath
}

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    $result.dashboardPath
}
