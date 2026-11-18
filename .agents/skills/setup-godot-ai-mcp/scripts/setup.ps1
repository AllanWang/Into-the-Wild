<#
.SYNOPSIS
    Automated cross-device agent setup script for Into the Wild + Godot AI MCP (hi-godot/godot-ai).
.DESCRIPTION
    1. Auto-discovers Godot 4.7+ (via -GodotBin, $env:GODOT_BIN, PATH, Steam libraries, Winget, Scoop).
    2. Downloads and extracts the requested or latest hi-godot/godot-ai plugin into addons/godot_ai.
    3. Ensures _mcp_game_helper and res://addons/godot_ai/plugin.cfg are registered in project.godot.
    4. Configures mcp_config.json for Antigravity (~/.gemini/config/mcp_config.json & ~/.gemini/antigravity/mcp_config.json).
    5. Registers this project as favorite=true in Godot's projects.cfg (editor_data and/or %APPDATA%\Godot).
    6. Runs a one-time headless Godot import & syntax check.
#>
param (
    [string]$Version = "",
    [string]$GodotBin = "",
    [switch]$SkipProjectLink
)

$ErrorActionPreference = "Stop"
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8NoBom {
    param (
        [string]$Path,
        [string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8NoBom)
}

function Resolve-GodotExecutable {
    param ([string]$ExplicitPath = "")

    $Candidates = New-Object System.Collections.Generic.List[string]
    if ($ExplicitPath) { $Candidates.Add($ExplicitPath) }
    if ($env:GODOT_BIN) { $Candidates.Add($env:GODOT_BIN) }

    foreach ($CmdName in @("godot", "godot4")) {
        $Cmd = Get-Command $CmdName -ErrorAction SilentlyContinue
        if ($Cmd -and $Cmd.Source) {
            $Candidates.Add($Cmd.Source)
        }
    }

    $SteamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($DefaultSteam in @(
        "C:\Program Files (x86)\Steam",
        "C:\Program Files\Steam"
    )) {
        if (Test-Path $DefaultSteam) {
            $SteamRoots.Add($DefaultSteam)
            $Vdf = Join-Path $DefaultSteam "steamapps\libraryfolders.vdf"
            if (Test-Path $Vdf) {
                $VdfText = Get-Content $Vdf -Raw
                foreach ($Match in [regex]::Matches($VdfText, '"path"\s+"([^"]+)"')) {
                    $LibRoot = ($Match.Groups[1].Value -replace '\\\\', '\')
                    if ($LibRoot -and -not $SteamRoots.Contains($LibRoot)) {
                        $SteamRoots.Add($LibRoot)
                    }
                }
            }
        }
    }

    foreach ($Root in $SteamRoots) {
        $Candidates.Add((Join-Path $Root "steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"))
        $Candidates.Add((Join-Path $Root "steamapps\common\Godot Engine\godot.exe"))
    }

    if ($env:LOCALAPPDATA) {
        $Candidates.Add((Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\godot.exe"))
    }
    if ($env:USERPROFILE) {
        $Candidates.Add((Join-Path $env:USERPROFILE "scoop\apps\godot\current\godot.exe"))
    }

    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath $Candidate -PathType Leaf)) {
            return (Resolve-Path -LiteralPath $Candidate).Path
        }
    }
    return $null
}

function Ensure-ProjectGodotRegistration {
    param ([string]$ProjectGodotPath)

    if (-not (Test-Path $ProjectGodotPath)) {
        return
    }

    $Content = Get-Content -Path $ProjectGodotPath -Raw
    $Updated = $false

    if ($Content -notmatch "res://addons/godot_ai/plugin\.cfg") {
        Write-Host "Registering editor plugin in project.godot..." -ForegroundColor Cyan
        if ($Content -match "(?ms)^\[editor_plugins\](.*?)(?=^\[|\z)") {
            $SectionBlock = $Matches[0]
            if ($SectionBlock -match 'enabled=PackedStringArray\(\s*\)') {
                $NewBlock = $SectionBlock -replace 'enabled=PackedStringArray\(\s*\)', 'enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg")'
            } elseif ($SectionBlock -match 'enabled=PackedStringArray\(') {
                $NewBlock = $SectionBlock -replace 'enabled=PackedStringArray\(', 'enabled=PackedStringArray("res://addons/godot_ai/plugin.cfg", '
            } else {
                $NewBlock = $SectionBlock.TrimEnd("`r", "`n") + "`r`nenabled=PackedStringArray(`"res://addons/godot_ai/plugin.cfg`")`r`n`r`n"
            }
            $Content = $Content.Substring(0, $Matches.Index) + $NewBlock + $Content.Substring($Matches.Index + $Matches.Length)
        } else {
            $PluginSection = "`r`n[editor_plugins]`r`n`r`nenabled=PackedStringArray(`"res://addons/godot_ai/plugin.cfg`")`r`n"
            if ($Content -match "(?m)^\[global_group\]") {
                $Content = [regex]::Replace($Content, "(?m)^(\[global_group\])", "$PluginSection`r`n`$1", 1)
            } elseif ($Content -match "(?m)^\[autoload\]") {
                $Content = [regex]::Replace($Content, "(?m)^(\[autoload\])", "$PluginSection`r`n`$1", 1)
            } else {
                $Content = $Content.TrimEnd("`r", "`n") + "`r`n" + $PluginSection
            }
        }
        $Updated = $true
    }

    if ($Content -notmatch "(?m)^_mcp_game_helper=") {
        Write-Host "Registering _mcp_game_helper autoload in project.godot..." -ForegroundColor Cyan
        $AutoloadLine = '_mcp_game_helper="*res://addons/godot_ai/runtime/game_helper.gd"'
        if ($Content -match "(?ms)^\[autoload\]\r?\n\r?\n") {
            $Content = [regex]::Replace($Content, "(?m)^(\[autoload\]\r?\n\r?\n)", "`$1$AutoloadLine`r`n", 1)
        } elseif ($Content -match "(?m)^\[autoload\]\r?\n") {
            $Content = [regex]::Replace($Content, "(?m)^(\[autoload\]\r?\n)", "`$1$AutoloadLine`r`n", 1)
        } else {
            $Content = $Content.TrimEnd("`r", "`n") + "`r`n`r`n[autoload]`r`n`r`n$AutoloadLine`r`n"
        }
        $Updated = $true
    }

    if ($Updated) {
        Write-Utf8NoBom -Path $ProjectGodotPath -Content $Content
    }
}

function Update-McpConfigs {
    param ([string]$TargetVersion)

    $UvxCmd = "uvx"
    $CmdLookup = Get-Command uvx -ErrorAction SilentlyContinue
    if ($CmdLookup -and $CmdLookup.Source) {
        $UvxCmd = $CmdLookup.Source
    } elseif ($env:USERPROFILE -and (Test-Path (Join-Path $env:USERPROFILE ".local\bin\uvx.exe"))) {
        $UvxCmd = Join-Path $env:USERPROFILE ".local\bin\uvx.exe"
    }

    $CandidatePaths = @(
        (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
        (Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json")
    )

    $Targets = @($CandidatePaths | Where-Object { Test-Path $_ })
    if ($Targets.Count -eq 0) {
        $Targets = @($CandidatePaths[0])
    }

    foreach ($McpPath in $Targets) {
        Write-Host "Configuring MCP server entry in $McpPath..." -ForegroundColor Cyan
        $ParentDir = Split-Path -Parent $McpPath
        if (-not (Test-Path $ParentDir)) {
            New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
        }

        $Json = $null
        if (Test-Path $McpPath) {
            $Raw = Get-Content $McpPath -Raw
            if ($Raw -and $Raw.Trim()) {
                $Json = $Raw | ConvertFrom-Json
            }
        }
        if (-not $Json) {
            $Json = [PSCustomObject]@{}
        }
        if (-not $Json.mcpServers) {
            $Json | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
        }

        $GodotServer = [PSCustomObject]@{
            command  = $UvxCmd
            args     = @(
                "--from",
                "godot-ai==$TargetVersion",
                "godot-ai",
                "attach",
                "--port",
                "8000",
                "--ws-port",
                "9500"
            )
            disabled = $false
        }
        $Json.mcpServers | Add-Member -MemberType NoteProperty -Name "godot-ai" -Value $GodotServer -Force
        Write-Utf8NoBom -Path $McpPath -Content (($Json | ConvertTo-Json -Depth 10) + "`r`n")
    }
}

function Link-GodotProjectManager {
    param (
        [string]$ProjectPath,
        [string]$GodotExePath
    )

    $NormalizedPath = ($ProjectPath -replace '\\', '/').TrimEnd('/')
    $CfgTargets = New-Object System.Collections.Generic.List[string]

    if ($GodotExePath) {
        $GodotDir = Split-Path -Parent $GodotExePath
        $HasSelfContained = (Test-Path (Join-Path $GodotDir "editor_data")) -or
            (Test-Path (Join-Path $GodotDir "_sc_")) -or
            (Test-Path (Join-Path $GodotDir "._sc_"))
        if ($HasSelfContained) {
            $CfgTargets.Add((Join-Path $GodotDir "editor_data\projects.cfg"))
        }
    }

    if ($env:APPDATA) {
        $AppDataGodotDir = Join-Path $env:APPDATA "Godot"
        if ($CfgTargets.Count -eq 0 -or (Test-Path $AppDataGodotDir)) {
            $CfgTargets.Add((Join-Path $AppDataGodotDir "projects.cfg"))
        }
    }

    $HeaderPattern = "(?m)^\[" + [regex]::Escape($NormalizedPath) + "\]\s*$"
    foreach ($CfgPath in $CfgTargets) {
        $ParentDir = Split-Path -Parent $CfgPath
        if (-not (Test-Path $ParentDir)) {
            New-Item -ItemType Directory -Path $ParentDir -Force | Out-Null
        }

        $Existing = ""
        if (Test-Path $CfgPath) {
            $Existing = Get-Content $CfgPath -Raw
        }

        if ($Existing -match $HeaderPattern) {
            Write-Host "Godot Project Manager already linked in $CfgPath" -ForegroundColor DarkGray
            continue
        }

        $Entry = "[$NormalizedPath]`r`n`r`nfavorite=true`r`n"
        if ($Existing -and $Existing.Trim()) {
            $NewContent = $Existing.TrimEnd("`r", "`n") + "`r`n`r`n" + $Entry
        } else {
            $NewContent = $Entry
        }
        Write-Utf8NoBom -Path $CfgPath -Content $NewContent
        Write-Host "Linked project in Godot Project Manager: $CfgPath" -ForegroundColor Cyan
    }
}

$ProjectRoot = (Resolve-Path "$PSScriptRoot\..\..\..\..").Path
Write-Host "Setting up Into the Wild + Godot AI MCP in: $ProjectRoot" -ForegroundColor Cyan

# 1. Determine release version & download URL
if (-not $Version) {
    Write-Host "Fetching latest hi-godot/godot-ai release from GitHub API..."
    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/hi-godot/godot-ai/releases/latest" -Headers @{"User-Agent" = "Godot-MCP-Setup"}
    $Version = $Release.tag_name.TrimStart('v')
    $Asset = $Release.assets | Where-Object { $_.name -eq "godot-ai-v4-plugin.zip" }
    if (-not $Asset) {
        $Asset = $Release.assets | Where-Object { $_.name -like "*plugin.zip" } | Select-Object -First 1
    }
    $DownloadUrl = $Asset.browser_download_url
} else {
    $DownloadUrl = "https://github.com/hi-godot/godot-ai/releases/download/v$Version/godot-ai-v4-plugin.zip"
}

Write-Host "Target Godot AI version: $Version" -ForegroundColor Green
Write-Host "Download URL: $DownloadUrl"

# 2. Download and extract addons/godot_ai
$TempZip = Join-Path $env:TEMP "godot-ai-plugin-$Version.zip"
$TempExtract = Join-Path $env:TEMP "godot-ai-extract-$Version"

try {
    if (Test-Path $TempExtract) {
        Remove-Item -Recurse -Force $TempExtract
    }

    Write-Host "Downloading release zip..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempZip

    Write-Host "Extracting archive..."
    Expand-Archive -Path $TempZip -DestinationPath $TempExtract -Force

    $SourceAddon = Join-Path $TempExtract "addons\godot_ai"
    $TargetAddonsDir = Join-Path $ProjectRoot "addons"
    $TargetAddon = Join-Path $TargetAddonsDir "godot_ai"

    if (-not (Test-Path $TargetAddonsDir)) {
        New-Item -ItemType Directory -Path $TargetAddonsDir | Out-Null
    }
    if (Test-Path $TargetAddon) {
        Remove-Item -Recurse -Force $TargetAddon
    }

    Write-Host "Installing addon into $TargetAddon..."
    Copy-Item -Path $SourceAddon -Destination $TargetAddon -Recurse -Force
} finally {
    if (Test-Path $TempZip) { Remove-Item -Force $TempZip -ErrorAction SilentlyContinue }
    if (Test-Path $TempExtract) { Remove-Item -Recurse -Force $TempExtract -ErrorAction SilentlyContinue }
}

# 3. Ensure project.godot plugin & autoload registrations
Ensure-ProjectGodotRegistration -ProjectGodotPath (Join-Path $ProjectRoot "project.godot")

# 4. Update MCP client configurations
Update-McpConfigs -TargetVersion $Version

# 5. Locate Godot & link into Project Manager
$GodotExe = Resolve-GodotExecutable -ExplicitPath $GodotBin
if (-not $SkipProjectLink) {
    Link-GodotProjectManager -ProjectPath $ProjectRoot -GodotExePath $GodotExe
}

# 6. Run one-time headless import & sanity check
if ($GodotExe) {
    Write-Host "Running one-time headless import & verification with: $GodotExe" -ForegroundColor Green
    & $GodotExe --headless --path "$ProjectRoot" --quit
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Headless verification succeeded! Godot AI MCP is ready." -ForegroundColor Green
    } else {
        Write-Warning "Headless check exited with code: $LASTEXITCODE"
    }
} else {
    Write-Warning "Godot 4.7+ executable not found automatically. Set GODOT_BIN or pass -GodotBin and run headless import manually."
}

Write-Host "Setup complete! Ask the user to open 'Into the Wild' in the Godot Editor (never launch Godot GUI from an agent shell)." -ForegroundColor Green
