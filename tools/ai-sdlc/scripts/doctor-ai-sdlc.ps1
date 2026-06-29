[CmdletBinding()]
param(
    [string] $Root = ".",
    [string] $ReportDirectory = ".sdlc/doctor",
    [string] $JsonOutputPath = "sdlc-doctor-report.json",
    [string] $MarkdownOutputPath = "sdlc-doctor-report.md",
    [switch] $FailOnWarnings,
    [switch] $Pretty
)

. "$PSScriptRoot/ai-sdlc-common.ps1"

function Add-Finding {
    param(
        [System.Collections.Generic.List[object]] $List,
        [string] $Code,
        [string] $Message,
        [string] $Path = ""
    )

    $List.Add([ordered]@{
        code = $Code
        message = $Message
        path = $Path
    })
}

function Test-RelativeFile {
    param(
        [string] $RootPath,
        [string] $RelativePath,
        [System.Collections.Generic.List[object]] $Blockers
    )

    $path = Join-Path $RootPath $RelativePath
    $present = Test-Path -LiteralPath $path
    if (-not $present) {
        Add-Finding -List $Blockers -Code "missing_required_file" -Message "Missing required AI SDLC file." -Path $RelativePath
    }

    return [ordered]@{
        path = $RelativePath
        present = $present
        sizeBytes = if ($present) { (Get-Item -LiteralPath $path).Length } else { 0 }
    }
}

$rootPath = Resolve-AiSdlcRoot -Root $Root
$reportRoot = if ([System.IO.Path]::IsPathRooted($ReportDirectory)) { $ReportDirectory } else { Join-Path $rootPath $ReportDirectory }
if (-not (Test-Path -LiteralPath $reportRoot)) {
    New-Item -ItemType Directory -Force -Path $reportRoot | Out-Null
}

$blockers = [System.Collections.Generic.List[object]]::new()
$warnings = [System.Collections.Generic.List[object]]::new()
$checks = [System.Collections.Generic.List[object]]::new()

$requiredFiles = @(
    "AGENTS.md",
    "docs/SDLC/README.md",
    "docs/SDLC/ai_sdlc_overview.md",
    "docs/SDLC/execution_lanes.md",
    "docs/LLM/llm_code_generation_do_dont.md",
    "docs/LLM/canonical_naming_rules.md",
    "tools/ai-sdlc/config/project-profile.yaml",
    "tools/ai-sdlc/config/context_memory.yaml",
    "tools/ai-sdlc/config/integrations.yaml",
    "tools/ai-sdlc/config/token_budget.yaml",
    "tools/ai-sdlc/config/execution_lanes.yaml",
    "tools/ai-sdlc/config/role_flow.yaml",
    "tools/ai-sdlc/config/safety_gates.yaml",
    "tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.ps1",
    "tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.ps1",
    "tools/ai-sdlc/scripts/select-sdlc-lane.ps1",
    "tools/ai-sdlc/scripts/verify-sdlc-compliance.ps1",
    "tools/ai-sdlc/scripts/doctor-ai-sdlc.ps1",
    "dashboard/index.html",
    "dashboard/styles.css",
    "dashboard/app.js"
)

foreach ($relative in $requiredFiles) {
    $checks.Add((Test-RelativeFile -RootPath $rootPath -RelativePath $relative -Blockers $blockers))
}

$profile = $null
try {
    $profile = Read-AiSdlcProfile -Root $rootPath
} catch {
    Add-Finding -List $blockers -Code "profile_unreadable" -Message $_.Exception.Message -Path "tools/ai-sdlc/config/project-profile.yaml"
}

if ($profile) {
    if ($profile.projectName -eq "UnknownProject" -or [string]::IsNullOrWhiteSpace($profile.projectName)) {
        Add-Finding -List $warnings -Code "profile_project_name_missing" -Message "Set project_name in project-profile.yaml." -Path "tools/ai-sdlc/config/project-profile.yaml"
    }

    if (@($profile.buildCommands).Count -eq 0) {
        Add-Finding -List $warnings -Code "build_commands_missing" -Message "No build_commands configured; CI evidence may be weak." -Path "tools/ai-sdlc/config/project-profile.yaml"
    }

    if (@($profile.testCommands).Count -eq 0) {
        Add-Finding -List $warnings -Code "test_commands_missing" -Message "No test_commands configured; validation cannot prove behavior." -Path "tools/ai-sdlc/config/project-profile.yaml"
    }

    if (@($profile.protectedSurfaces).Count -eq 0) {
        Add-Finding -List $warnings -Code "protected_surfaces_missing" -Message "No protected_surfaces configured; risky areas may not be obvious to agents." -Path "tools/ai-sdlc/config/project-profile.yaml"
    }

    if (@($profile.architectureAreas.Keys).Count -eq 0) {
        Add-Finding -List $warnings -Code "architecture_areas_missing" -Message "No architecture_areas configured; impact analysis will be less precise." -Path "tools/ai-sdlc/config/project-profile.yaml"
    }
}

$scriptsRoot = Join-Path $rootPath "tools/ai-sdlc/scripts"
if (Test-Path -LiteralPath $scriptsRoot) {
    Get-ChildItem -LiteralPath $scriptsRoot -Filter "*.ps1" -File | ForEach-Object {
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
        foreach ($parseError in @($parseErrors)) {
            Add-Finding -List $blockers -Code "powershell_parse_error" -Message $parseError.Message -Path (ConvertTo-SdlcPath -Path $_.FullName.Substring($rootPath.Length).TrimStart("\", "/"))
        }
    }
} else {
    Add-Finding -List $blockers -Code "scripts_directory_missing" -Message "Missing tools/ai-sdlc/scripts directory." -Path "tools/ai-sdlc/scripts"
}

$shellWrappers = @(
    "tools/ai-sdlc/scripts/run-ai-sdlc-pipeline.sh",
    "tools/ai-sdlc/scripts/run-ai-sdlc-orchestrator.sh",
    "tools/ai-sdlc/scripts/verify-sdlc-compliance.sh",
    "tools/ai-sdlc/scripts/doctor-ai-sdlc.sh"
)
foreach ($wrapper in $shellWrappers) {
    if (-not (Test-Path -LiteralPath (Join-Path $rootPath $wrapper))) {
        Add-Finding -List $warnings -Code "shell_wrapper_missing" -Message "macOS/Linux wrapper is missing." -Path $wrapper
    }
}

$workflowPath = Join-Path $rootPath ".github/workflows/ai-sdlc.yml"
if (-not (Test-Path -LiteralPath $workflowPath)) {
    Add-Finding -List $warnings -Code "github_workflow_missing" -Message "GitHub workflow is not installed. This is optional, but CI will not verify AI SDLC automatically." -Path ".github/workflows/ai-sdlc.yml"
}

$manifestPath = Join-Path $rootPath ".sdlc/ai-sdlc-install-manifest.json"
if (-not (Test-Path -LiteralPath $manifestPath)) {
    Add-Finding -List $warnings -Code "install_manifest_missing" -Message "Install manifest is missing. Update/uninstall safety will be weaker." -Path ".sdlc/ai-sdlc-install-manifest.json"
}

try {
    $probePath = Join-Path $reportRoot ".write-probe"
    Set-Content -LiteralPath $probePath -Value "ok"
    Remove-Item -LiteralPath $probePath -Force
} catch {
    Add-Finding -List $blockers -Code "sdlc_report_directory_not_writable" -Message $_.Exception.Message -Path (ConvertTo-SdlcPath -Path $reportRoot)
}

$decision = if ($blockers.Count -gt 0) {
    "blocked"
} elseif ($warnings.Count -gt 0) {
    "review_required"
} else {
    "proceed"
}

$passed = if ($decision -eq "proceed") { $true } elseif ($decision -eq "review_required" -and -not $FailOnWarnings) { $true } else { $false }

$result = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
    root = $rootPath
    reportDirectory = $reportRoot
    passed = $passed
    decision = $decision
    failOnWarnings = [bool]$FailOnWarnings
    project = if ($profile) {
        [ordered]@{
            name = $profile.projectName
            profile = $profile.profileName
            stack = $profile.primaryStack
            buildCommands = @($profile.buildCommands).Count
            testCommands = @($profile.testCommands).Count
            lintCommands = @($profile.lintCommands).Count
            protectedSurfaces = @($profile.protectedSurfaces).Count
            architectureAreas = @($profile.architectureAreas.Keys).Count
        }
    } else { $null }
    blockers = @($blockers)
    warnings = @($warnings)
    requiredFiles = @($checks)
}

$lines = @(
    "- Passed: $passed",
    "- Decision: $decision",
    "- Blockers: $($blockers.Count)",
    "- Warnings: $($warnings.Count)",
    "- Project: $(if ($profile) { $profile.projectName } else { 'unknown' })",
    "- Profile: $(if ($profile) { $profile.profileName } else { 'unknown' })"
)

$jsonPath = if ([System.IO.Path]::IsPathRooted($JsonOutputPath)) { $JsonOutputPath } else { Join-Path $reportRoot $JsonOutputPath }
$mdPath = if ([System.IO.Path]::IsPathRooted($MarkdownOutputPath)) { $MarkdownOutputPath } else { Join-Path $reportRoot $MarkdownOutputPath }
Write-SdlcJsonAndMarkdown -Data $result -JsonPath $jsonPath -MarkdownPath $mdPath -Title "AI SDLC Doctor Report" -Lines $lines

if ($Pretty) {
    $result | ConvertTo-Json -Depth 12
} else {
    Get-Content -LiteralPath $jsonPath -Raw
}

if (-not $passed) {
    if ($decision -eq "review_required") { exit 2 }
    exit 1
}
