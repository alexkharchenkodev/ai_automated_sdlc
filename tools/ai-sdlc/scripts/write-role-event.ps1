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

    $json = $Value | ConvertTo-Json -Depth 20 -Compress
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
$lanePath = Join-Path $reportRoot "sdlc-lane-report.json"
$safeChangePath = Join-Path $reportRoot "sdlc-safe-change-report.json"
$compliancePath = Join-Path $reportRoot "sdlc-compliance-report.json"
$contextPath = Join-Path $reportRoot "sdlc-context-memory-report.json"
$integrationsPath = Join-Path $reportRoot "sdlc-integrations-report.json"
$tokenPath = Join-Path $reportRoot "sdlc-token-usage-report.json"
$summary = if (Test-Path -LiteralPath $summaryPath) { Get-Content -LiteralPath $summaryPath -Raw | ConvertFrom-Json } else { $null }
$lane = if (Test-Path -LiteralPath $lanePath) { Get-Content -LiteralPath $lanePath -Raw | ConvertFrom-Json } else { $null }
$safeChange = if (Test-Path -LiteralPath $safeChangePath) { Get-Content -LiteralPath $safeChangePath -Raw | ConvertFrom-Json } else { $null }
$compliance = if (Test-Path -LiteralPath $compliancePath) { Get-Content -LiteralPath $compliancePath -Raw | ConvertFrom-Json } else { $null }
$contextMemory = if (Test-Path -LiteralPath $contextPath) { Get-Content -LiteralPath $contextPath -Raw | ConvertFrom-Json } else { $null }
$integrations = if (Test-Path -LiteralPath $integrationsPath) { Get-Content -LiteralPath $integrationsPath -Raw | ConvertFrom-Json } else { $null }
$tokenUsage = if (Test-Path -LiteralPath $tokenPath) { Get-Content -LiteralPath $tokenPath -Raw | ConvertFrom-Json } else { $null }
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
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_LANE" -Value $lane))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_SAFETY" -Value $safeChange))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_COMPLIANCE" -Value $compliance))
$runtimeLines.Add((ConvertTo-JsAssignment -GlobalName "AI_SDLC_CONTEXT_MEMORY" -Value $contextMemory))
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
