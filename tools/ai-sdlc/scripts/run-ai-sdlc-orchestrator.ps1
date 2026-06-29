[CmdletBinding()]
param(
    [string] $Root = ".",
    [string[]] $ChangedFile = @(),
    [string] $ChangedFilesPath = "",
    [string] $Task = "",
    [string] $ReportDirectory = ".sdlc/local-pipeline",
    [string] $LiveDirectory = ".sdlc/live",
    [string] $RunId = "",
    [switch] $SkipValidationExecution,
    [switch] $OpenDashboard,
    [switch] $Pretty
)

$ErrorActionPreference = "Stop"

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Write-Event {
    param(
        [string] $Role,
        [string] $Status,
        [string] $Message,
        [string[]] $Artifact = @()
    )

    & "$PSScriptRoot/write-role-event.ps1" -Root $rootPath -RunId $RunId -Role $Role -Status $Status -Message $Message -Artifact $Artifact -LiveDirectory $LiveDirectory | Out-Null
}

function Write-SimpleArtifact {
    param(
        [string] $Path,
        [string] $Title,
        [string[]] $Lines
    )

    $directory = Split-Path -Parent $Path
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    $content = [System.Collections.Generic.List[string]]::new()
    $content.Add("# $Title")
    $content.Add("")
    foreach ($line in $Lines) { $content.Add($line) }
    Set-Content -LiteralPath $Path -Value $content
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
if (-not $RunId) {
    $RunId = "run-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
}

$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) {
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
}

if ($OpenDashboard) {
    & "$PSScriptRoot/start-ai-sdlc-dashboard.ps1" -Root $rootPath -LiveDirectory $LiveDirectory | Out-Null
}

$impactJson = Join-Path $reportRoot "sdlc-impact-report.json"
$impactMd = Join-Path $reportRoot "sdlc-impact-report.md"
$laneJson = Join-Path $reportRoot "sdlc-lane-report.json"
$laneMd = Join-Path $reportRoot "sdlc-lane-report.md"
$taskJson = Join-Path $reportRoot "sdlc-task-intake-report.json"
$taskMd = Join-Path $reportRoot "sdlc-task-intake-report.md"
$contextJson = Join-Path $reportRoot "sdlc-context-memory-report.json"
$contextMd = Join-Path $reportRoot "sdlc-context-memory-report.md"
$integrationsJson = Join-Path $reportRoot "sdlc-integrations-report.json"
$integrationsMd = Join-Path $reportRoot "sdlc-integrations-report.md"
$impactedTestsJson = Join-Path $reportRoot "sdlc-impacted-tests.json"
$impactedTestsMd = Join-Path $reportRoot "sdlc-impacted-tests.md"
$rollbackJson = Join-Path $reportRoot "sdlc-rollback-plan.json"
$rollbackMd = Join-Path $reportRoot "sdlc-rollback-plan.md"
$baBrief = Join-Path $reportRoot "ba-brief.md"
$architectureBrief = Join-Path $reportRoot "architecture-brief.md"
$reuseScan = Join-Path $reportRoot "reuse-scan.md"
$designNotes = Join-Path $reportRoot "design-notes.md"
$implementationSummary = Join-Path $reportRoot "implementation-summary.md"
$codeReviewReport = Join-Path $reportRoot "code-review-report.md"
$planJson = Join-Path $reportRoot "sdlc-validation-plan.json"
$planMd = Join-Path $reportRoot "sdlc-validation-plan.md"
$validationJson = Join-Path $reportRoot "sdlc-selected-validation-report.json"
$validationMd = Join-Path $reportRoot "sdlc-selected-validation-report.md"
$safeJson = Join-Path $reportRoot "sdlc-safe-change-report.json"
$safeMd = Join-Path $reportRoot "sdlc-safe-change-report.md"
$tokenJson = Join-Path $reportRoot "sdlc-token-usage-report.json"
$tokenMd = Join-Path $reportRoot "sdlc-token-usage-report.md"
$bundleJson = Join-Path $reportRoot "sdlc-evidence-bundle.json"
$bundleMd = Join-Path $reportRoot "sdlc-evidence-bundle.md"
$complianceJson = Join-Path $reportRoot "sdlc-compliance-report.json"
$complianceMd = Join-Path $reportRoot "sdlc-compliance-report.md"

try {
    Write-Event -Role "intake" -Status "running" -Message "Analyzing changed files and normalizing task intake."
    & "$PSScriptRoot/analyze-impact.ps1" -Root $rootPath -ChangedFile $ChangedFile -ChangedFilesPath $ChangedFilesPath -JsonOutputPath $impactJson -MarkdownOutputPath $impactMd | Out-Null
    & "$PSScriptRoot/select-sdlc-lane.ps1" -Root $rootPath -ImpactReportPath $impactJson -JsonOutputPath $laneJson -MarkdownOutputPath $laneMd | Out-Null
    & "$PSScriptRoot/write-task-intake-report.ps1" -Root $rootPath -Task $Task -ImpactReportPath $impactJson -JsonOutputPath $taskJson -MarkdownOutputPath $taskMd | Out-Null
    $lane = Get-Content -LiteralPath $laneJson -Raw | ConvertFrom-Json
    Write-Event -Role "intake" -Status "completed" -Message "Impact, lane, and task intake reports generated. Lane: $($lane.lane)." -Artifact @($impactJson, $laneJson, $taskJson)

    $impact = Get-Content -LiteralPath $impactJson -Raw | ConvertFrom-Json
    $taskReport = Get-Content -LiteralPath $taskJson -Raw | ConvertFrom-Json
    $profile = Read-AiSdlcProfile -Root $rootPath

    Write-Event -Role "ba" -Status "running" -Message "Preparing acceptance, complexity, and non-goal brief."
    Write-SimpleArtifact -Path $baBrief -Title "BA Brief" -Lines @(
        "- Task: $($taskReport.task.title)",
        "- Primary target: $($taskReport.task.primaryTarget)",
        "- Changed areas: $(@($impact.changedAreas) -join ', ')",
        "- Complexity: $($impact.complexity)",
        "- Risk score: $($impact.riskScore)",
        "- Execution lane: $($lane.lane) ($($lane.title))",
        "- Acceptance criteria:",
        "  - Change remains scoped to the requested target.",
        "  - Validation plan is run or skip is justified.",
        "  - Evidence bundle is generated."
    )
    Write-Event -Role "ba" -Status "completed" -Message "BA brief generated." -Artifact @($baBrief)

    Write-Event -Role "architecture" -Status "running" -Message "Checking profile boundaries, protected surfaces, and risk signals."
    & "$PSScriptRoot/check-integrations.ps1" -Root $rootPath -JsonOutputPath $integrationsJson -MarkdownOutputPath $integrationsMd | Out-Null
    $integrations = Get-Content -LiteralPath $integrationsJson -Raw | ConvertFrom-Json
    Write-SimpleArtifact -Path $architectureBrief -Title "Architecture Brief" -Lines @(
        "- Project profile: $($profile.profileName)",
        "- Primary stack: $($profile.primaryStack)",
        "- Architecture areas touched: $(@($impact.changedAreas) -join ', ')",
        "- Risk signals: $(@($impact.riskSignals) -join ', ')",
        "- Execution lane: $($lane.lane)",
        "- Lane requires validation execution: $($lane.requireValidationExecution)",
        "- Human approval required: $($impact.requiresHumanApproval)",
        "- Integration readiness: $($integrations.decision)",
        "- Enabled integrations: $($integrations.enabledIntegrations)",
        "- Protected surfaces:",
        ($profile.protectedSurfaces | ForEach-Object { "  - $_" })
    )
    Write-Event -Role "architecture" -Status "completed" -Message "Architecture brief and integration readiness generated." -Artifact @($architectureBrief, $integrationsJson)

    Write-Event -Role "memory_reuse" -Status "running" -Message "Recording required local memory and reuse scan."
    & "$PSScriptRoot/write-context-memory-report.ps1" -Root $rootPath -JsonOutputPath $contextJson -MarkdownOutputPath $contextMd | Out-Null
    $contextMemory = Get-Content -LiteralPath $contextJson -Raw | ConvertFrom-Json
    Write-SimpleArtifact -Path $reuseScan -Title "Memory And Reuse Scan" -Lines @(
        "- Search local code and docs before inventing new components, APIs, workflows, or schemas.",
        "- Context memory decision: $($contextMemory.decision)",
        "- Enabled context providers: $($contextMemory.enabledProviders)",
        "- Available local context sources: $($contextMemory.availableSources)",
        "- Suggested roots from profile:",
        ($profile.architectureAreas.Keys | ForEach-Object {
            $paths = @($profile.architectureAreas[$_]) -join ', '
            "  - ${_}: $paths"
        }),
        "- Agent adapters should attach concrete search evidence here when performing implementation."
    )
    Write-Event -Role "memory_reuse" -Status "completed" -Message "Reuse scan and context memory report generated." -Artifact @($reuseScan, $contextJson)

    $designNeeded = (@($impact.changedAreas) -match "ui|app|application|design|frontend").Count -gt 0
    if ($designNeeded) {
        Write-Event -Role "design" -Status "running" -Message "Checking user-facing design and visual evidence needs."
        Write-SimpleArtifact -Path $designNotes -Title "Design Notes" -Lines @(
            "- User-facing impact is possible based on changed areas.",
            "- Check interaction states, empty/error states, accessibility, and visual evidence needs.",
            "- Attach screenshots or design review evidence when applicable."
        )
        Write-Event -Role "design" -Status "completed" -Message "Design notes generated." -Artifact @($designNotes)
    } else {
        Write-Event -Role "design" -Status "skipped" -Message "No likely user-facing design impact detected."
    }

    Write-Event -Role "engineering" -Status "skipped" -Message "Portable orchestrator does not edit product code. Active AI client should emit engineering events while implementing." -Artifact @($implementationSummary)
    Write-SimpleArtifact -Path $implementationSummary -Title "Implementation Summary" -Lines @(
        "- The portable orchestrator does not edit product code by itself.",
        "- Codex, Claude, Copilot, or another file-editing AI should perform implementation and update this artifact.",
        "- Emit role events with write-role-event.ps1 while editing."
    )

    Write-Event -Role "code_review" -Status "running" -Message "Preparing automated review checklist."
    Write-SimpleArtifact -Path $codeReviewReport -Title "Code Review Report" -Lines @(
        "- Review changed files for defects, regressions, boundary violations, and missing tests.",
        "- Automated status: checklist generated; human or AI code review should attach findings.",
        "- Risk score from impact: $($impact.riskScore)"
    )
    Write-Event -Role "code_review" -Status "completed" -Message "Code review checklist generated." -Artifact @($codeReviewReport)

    Write-Event -Role "test_planning" -Status "running" -Message "Selecting validation commands from project profile."
    & "$PSScriptRoot/select-impacted-tests.ps1" -Root $rootPath -ImpactReportPath $impactJson -JsonOutputPath $impactedTestsJson -MarkdownOutputPath $impactedTestsMd | Out-Null
    & "$PSScriptRoot/write-rollback-plan.ps1" -Root $rootPath -ImpactReportPath $impactJson -JsonOutputPath $rollbackJson -MarkdownOutputPath $rollbackMd | Out-Null
    & "$PSScriptRoot/select-validation.ps1" -Root $rootPath -ImpactReportPath $impactJson -JsonOutputPath $planJson -MarkdownOutputPath $planMd | Out-Null
    Write-Event -Role "test_planning" -Status "completed" -Message "Validation, impacted-test, and rollback plans generated." -Artifact @($planJson, $impactedTestsJson, $rollbackJson)

    Write-Event -Role "test_execution" -Status "running" -Message "Running selected validation plan."
    & "$PSScriptRoot/run-validation-plan.ps1" -Root $rootPath -PlanPath $planJson -JsonOutputPath $validationJson -MarkdownOutputPath $validationMd -SkipExecution:$SkipValidationExecution | Out-Null
    $validation = Get-Content -LiteralPath $validationJson -Raw | ConvertFrom-Json
    $validationStatus = if ([bool]$validation.passed) { "completed" } else { "failed" }
    Write-Event -Role "test_execution" -Status $validationStatus -Message "Validation finished. Passed: $($validation.passed)." -Artifact @($validationJson)

    Write-Event -Role "evidence" -Status "running" -Message "Running safe-change gate."
    & "$PSScriptRoot/validate-safe-change.ps1" -Root $rootPath -ReportDirectory $reportRoot -JsonOutputPath $safeJson -MarkdownOutputPath $safeMd | Out-Null
    $safeChange = Get-Content -LiteralPath $safeJson -Raw | ConvertFrom-Json
    $safeStatus = if ([bool]$safeChange.passed) { "completed" } else { "blocked" }
    Write-Event -Role "evidence" -Status $safeStatus -Message "Safe-change decision: $($safeChange.decision)." -Artifact @($safeJson)

    Write-Event -Role "evidence" -Status "running" -Message "Estimating token usage for generated reports and changed files."
    & "$PSScriptRoot/estimate-token-usage.ps1" -Root $rootPath -ImpactReportPath $impactJson -ReportDirectory $reportRoot -JsonOutputPath $tokenJson -MarkdownOutputPath $tokenMd | Out-Null
    $tokenUsage = Get-Content -LiteralPath $tokenJson -Raw | ConvertFrom-Json
    $tokenStatus = if ($tokenUsage.decision -eq "blocked") { "blocked" } elseif ($tokenUsage.decision -eq "proceed") { "completed" } else { "waiting" }
    Write-Event -Role "evidence" -Status $tokenStatus -Message "Token estimate: $($tokenUsage.estimatedTokens), decision: $($tokenUsage.decision)." -Artifact @($tokenJson)

    Write-Event -Role "evidence" -Status "running" -Message "Building evidence bundle."
    & "$PSScriptRoot/write-evidence-bundle.ps1" -Root $rootPath -ReportDirectory $reportRoot -JsonOutputPath $bundleJson -MarkdownOutputPath $bundleMd | Out-Null
    $bundle = Get-Content -LiteralPath $bundleJson -Raw | ConvertFrom-Json
    $bundleStatus = if ([bool]$bundle.passed) { "completed" } else { "blocked" }
    Write-Event -Role "evidence" -Status $bundleStatus -Message "Evidence bundle decision: $($bundle.decision)." -Artifact @($bundleJson)

    Write-Event -Role "evidence" -Status "running" -Message "Verifying SDLC compliance verdict for the selected lane."
    & "$PSScriptRoot/verify-sdlc-compliance.ps1" -Root $rootPath -ReportDirectory $reportRoot -JsonOutputPath $complianceJson -MarkdownOutputPath $complianceMd -AllowReviewRequired | Out-Null
    $compliance = Get-Content -LiteralPath $complianceJson -Raw | ConvertFrom-Json
    $complianceStatus = if ($compliance.decision -eq "blocked") { "blocked" } elseif ($compliance.decision -eq "proceed") { "completed" } else { "waiting" }
    Write-Event -Role "evidence" -Status $complianceStatus -Message "Compliance decision: $($compliance.decision)." -Artifact @($complianceJson)

    $summary = [ordered]@{
        schemaVersion = 1
        generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        runId = $RunId
        passed = [bool]$bundle.passed
        reportDirectory = $reportRoot
        liveDirectory = (Get-AiSdlcLiveDirectory -Root $rootPath -LiveDirectory $LiveDirectory)
        dashboardPath = Join-Path (Join-Path (Get-AiSdlcLiveDirectory -Root $rootPath -LiveDirectory $LiveDirectory) "dashboard") "index.html"
        changedAreas = @($impact.changedAreas)
        complexity = $impact.complexity
        riskScore = $impact.riskScore
        lane = $lane.lane
        laneTitle = $lane.title
        requiresHumanApproval = [bool]$impact.requiresHumanApproval
        validationPassed = [bool]$validation.passed
        validationSkipped = [bool]$validation.skipped
        safeChangePassed = [bool]$safeChange.passed
        safeChangeDecision = $safeChange.decision
        contextMemoryDecision = $contextMemory.decision
        integrationsDecision = $integrations.decision
        tokenUsageDecision = $tokenUsage.decision
        estimatedTokens = $tokenUsage.estimatedTokens
        evidenceDecision = $bundle.decision
        complianceDecision = $compliance.decision
        compliancePassed = [bool]$compliance.passed
        reports = [ordered]@{
            impact = $impactJson
            lane = $laneJson
            taskIntake = $taskJson
            contextMemory = $contextJson
            integrations = $integrationsJson
            impactedTests = $impactedTestsJson
            rollbackPlan = $rollbackJson
            validationPlan = $planJson
            selectedValidation = $validationJson
            safeChange = $safeJson
            tokenUsage = $tokenJson
            evidenceBundle = $bundleJson
            compliance = $complianceJson
        }
    }

    $summaryPath = Join-Path $reportRoot "sdlc-summary.json"
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $summaryPath
    $doneStatus = if ($compliance.decision -eq "blocked") { "blocked" } else { "completed" }
    Write-Event -Role "done" -Status $doneStatus -Message "SDLC orchestration finished. Compliance decision: $($compliance.decision)." -Artifact @($summaryPath)

    if ($Pretty) { $summary | ConvertTo-Json -Depth 12 } else { Get-Content -LiteralPath $summaryPath -Raw }
    if ($compliance.decision -eq "blocked") {
        exit 1
    }
} catch {
    Write-Event -Role "done" -Status "failed" -Message $_.Exception.Message
    throw
}
