$ErrorActionPreference = "Stop"

function Resolve-AiSdlcRoot {
    param([string] $Root = ".")

    if (-not (Test-Path -LiteralPath $Root)) {
        throw "Root not found: $Root"
    }

    return (Resolve-Path -LiteralPath $Root).Path
}

function ConvertTo-SdlcPath {
    param([string] $Path)
    $normalized = ($Path -replace "\\", "/")
    while ($normalized.StartsWith("./")) {
        $normalized = $normalized.Substring(2)
    }
    return $normalized.TrimStart("/")
}

function Normalize-YamlValue {
    param([string] $Value)

    $trimmed = $Value.Trim()
    if ($trimmed.Length -ge 2) {
        if (($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) -or ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'"))) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }

    return $trimmed
}

function Read-SdlcText {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "File not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw
}

function Get-YamlScalar {
    param(
        [string[]] $Lines,
        [string] $Key,
        [string] $Default = ""
    )

    foreach ($line in $Lines) {
        if ($line -match "^$([regex]::Escape($Key)):\s*(.+?)\s*$") {
            return Normalize-YamlValue -Value $Matches[1]
        }
    }

    return $Default
}

function Get-YamlTopLevelList {
    param(
        [string[]] $Lines,
        [string] $Key
    )

    $values = [System.Collections.Generic.List[string]]::new()
    $inside = $false

    foreach ($line in $Lines) {
        if ($line -match "^$([regex]::Escape($Key)):\s*$") {
            $inside = $true
            continue
        }

        if ($inside -and $line -match "^\S") {
            break
        }

        if ($inside -and $line -match "^\s*-\s*(.+?)\s*$") {
            $values.Add((Normalize-YamlValue -Value $Matches[1]))
        }
    }

    return @($values)
}

function Get-YamlNestedPathMap {
    param(
        [string[]] $Lines,
        [string] $RootKey
    )

    $map = [ordered]@{}
    $insideRoot = $false
    $current = ""
    $insidePaths = $false

    foreach ($line in $Lines) {
        if ($line -match "^$([regex]::Escape($RootKey)):\s*$") {
            $insideRoot = $true
            continue
        }

        if ($insideRoot -and $line -match "^\S") {
            break
        }

        if (-not $insideRoot) {
            continue
        }

        if ($line -match "^\s{2}([A-Za-z0-9_-]+):\s*$") {
            $current = $Matches[1]
            $insidePaths = $false
            if (-not $map.Contains($current)) {
                $map[$current] = [System.Collections.Generic.List[string]]::new()
            }
            continue
        }

        if ($current -and $line -match "^\s{4}paths:\s*$") {
            $insidePaths = $true
            continue
        }

        if ($current -and $insidePaths -and $line -match "^\s{6}-\s*(.+?)\s*$") {
            $map[$current].Add((ConvertTo-SdlcPath -Path (Normalize-YamlValue -Value $Matches[1])))
        }

        if ($current -and $insidePaths -and $line -match "^\s{4}[A-Za-z0-9_-]+:\s*") {
            $insidePaths = $false
        }
    }

    return $map
}

function ConvertFrom-SdlcYamlValue {
    param([string] $Value)

    $normalized = Normalize-YamlValue -Value $Value
    if ($normalized -match "^(true|false)$") {
        return [System.Convert]::ToBoolean($normalized)
    }

    if ($normalized -match "^-?\d+$") {
        return [int]$normalized
    }

    return $normalized
}

function Get-YamlNestedObjectMap {
    param(
        [string[]] $Lines,
        [string] $RootKey
    )

    $map = [ordered]@{}
    $insideRoot = $false
    $current = ""
    $currentList = ""

    foreach ($line in $Lines) {
        if ($line -match "^$([regex]::Escape($RootKey)):\s*$") {
            $insideRoot = $true
            continue
        }

        if ($insideRoot -and $line -match "^\S") {
            break
        }

        if (-not $insideRoot) {
            continue
        }

        if ($line -match "^\s{2}([A-Za-z0-9_-]+):\s*$") {
            $current = $Matches[1]
            $currentList = ""
            if (-not $map.Contains($current)) {
                $map[$current] = [ordered]@{}
            }
            continue
        }

        if ($current -and $line -match "^\s{4}([A-Za-z0-9_-]+):\s*(.*?)\s*$") {
            $key = $Matches[1]
            $value = $Matches[2]
            if ($value) {
                $map[$current][$key] = ConvertFrom-SdlcYamlValue -Value $value
                $currentList = ""
            } else {
                $map[$current][$key] = [System.Collections.Generic.List[object]]::new()
                $currentList = $key
            }
            continue
        }

        if ($current -and $currentList -and $line -match "^\s{6}-\s*(.+?)\s*$") {
            $map[$current][$currentList].Add((ConvertFrom-SdlcYamlValue -Value $Matches[1]))
        }
    }

    return $map
}

function Get-YamlSectionScalarMap {
    param(
        [string[]] $Lines,
        [string] $RootKey
    )

    $map = [ordered]@{}
    $insideRoot = $false

    foreach ($line in $Lines) {
        if ($line -match "^$([regex]::Escape($RootKey)):\s*$") {
            $insideRoot = $true
            continue
        }

        if ($insideRoot -and $line -match "^\S") {
            break
        }

        if (-not $insideRoot) {
            continue
        }

        if ($line -match "^\s{2}([A-Za-z0-9_-]+):\s*(.+?)\s*$") {
            $map[$Matches[1]] = ConvertFrom-SdlcYamlValue -Value $Matches[2]
        }
    }

    return $map
}

function Read-AiSdlcProfile {
    param(
        [string] $Root = ".",
        [string] $ConfigPath = ""
    )

    $rootPath = Resolve-AiSdlcRoot -Root $Root
    $profilePath = if ($ConfigPath) { $ConfigPath } else { Join-Path $rootPath "tools/ai-sdlc/config/project-profile.yaml" }
    $text = Read-SdlcText -Path $profilePath
    $lines = $text -split "`r?`n"

    return [ordered]@{
        path = $profilePath
        projectName = Get-YamlScalar -Lines $lines -Key "project_name" -Default "UnknownProject"
        profileName = Get-YamlScalar -Lines $lines -Key "profile_name" -Default "generic"
        primaryStack = Get-YamlScalar -Lines $lines -Key "primary_stack" -Default "generic"
        projectRoot = Get-YamlScalar -Lines $lines -Key "project_root" -Default "."
        buildCommands = @(Get-YamlTopLevelList -Lines $lines -Key "build_commands")
        testCommands = @(Get-YamlTopLevelList -Lines $lines -Key "test_commands")
        lintCommands = @(Get-YamlTopLevelList -Lines $lines -Key "lint_commands")
        architectureAreas = Get-YamlNestedPathMap -Lines $lines -RootKey "architecture_areas"
        protectedSurfaces = @(Get-YamlTopLevelList -Lines $lines -Key "protected_surfaces")
    }
}

function Write-SdlcJsonAndMarkdown {
    param(
        [object] $Data,
        [string] $JsonPath,
        [string] $MarkdownPath,
        [string] $Title,
        [string[]] $Lines
    )

    $jsonDirectory = Split-Path -Parent $JsonPath
    if ($jsonDirectory -and -not (Test-Path -LiteralPath $jsonDirectory)) {
        New-Item -ItemType Directory -Force -Path $jsonDirectory | Out-Null
    }

    $markdownDirectory = Split-Path -Parent $MarkdownPath
    if ($markdownDirectory -and -not (Test-Path -LiteralPath $markdownDirectory)) {
        New-Item -ItemType Directory -Force -Path $markdownDirectory | Out-Null
    }

    $Data | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $JsonPath

    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add("# $Title")
    $out.Add("")
    foreach ($line in $Lines) {
        $out.Add($line)
    }
    Set-Content -LiteralPath $MarkdownPath -Value $out
}

function Get-AiSdlcRoleFlow {
    param(
        [string] $Root = ".",
        [string] $RoleFlowPath = ""
    )

    $rootPath = Resolve-AiSdlcRoot -Root $Root
    $path = if ($RoleFlowPath) { $RoleFlowPath } else { Join-Path $rootPath "tools/ai-sdlc/config/role_flow.yaml" }

    $fallback = @(
        [ordered]@{ id = "intake"; title = "Intake"; purpose = "Normalize task." },
        [ordered]@{ id = "ba"; title = "BA"; purpose = "Clarify acceptance." },
        [ordered]@{ id = "architecture"; title = "Architecture"; purpose = "Check boundaries." },
        [ordered]@{ id = "memory_reuse"; title = "Memory / Reuse"; purpose = "Check existing capabilities." },
        [ordered]@{ id = "design"; title = "Design / UX"; purpose = "Check user-facing behavior." },
        [ordered]@{ id = "engineering"; title = "Engineering"; purpose = "Implement changes." },
        [ordered]@{ id = "code_review"; title = "Code Review"; purpose = "Review risk." },
        [ordered]@{ id = "test_planning"; title = "Test Planning"; purpose = "Select validation." },
        [ordered]@{ id = "test_execution"; title = "Test Execution"; purpose = "Run validation." },
        [ordered]@{ id = "evidence"; title = "Evidence Bundle"; purpose = "Bundle evidence." },
        [ordered]@{ id = "done"; title = "Done / Handoff"; purpose = "Summarize outcome." }
    )

    if (-not (Test-Path -LiteralPath $path)) {
        return $fallback
    }

    $roles = [System.Collections.Generic.List[object]]::new()
    $current = $null
    foreach ($line in Get-Content -LiteralPath $path) {
        if ($line -match "^\s{2}-\s*id:\s*(.+?)\s*$") {
            if ($null -ne $current) { $roles.Add($current) }
            $current = [ordered]@{
                id = Normalize-YamlValue -Value $Matches[1]
                title = ""
                purpose = ""
            }
            continue
        }

        if ($null -ne $current -and $line -match "^\s{4}title:\s*(.+?)\s*$") {
            $current.title = Normalize-YamlValue -Value $Matches[1]
            continue
        }

        if ($null -ne $current -and $line -match "^\s{4}purpose:\s*(.+?)\s*$") {
            $current.purpose = Normalize-YamlValue -Value $Matches[1]
            continue
        }
    }

    if ($null -ne $current) { $roles.Add($current) }
    if ($roles.Count -eq 0) { return $fallback }
    return @($roles)
}

function Get-AiSdlcLiveDirectory {
    param(
        [string] $Root = ".",
        [string] $LiveDirectory = ".sdlc/live"
    )

    $rootPath = Resolve-AiSdlcRoot -Root $Root
    if ([System.IO.Path]::IsPathRooted($LiveDirectory)) {
        return $LiveDirectory
    }

    return Join-Path $rootPath $LiveDirectory
}
