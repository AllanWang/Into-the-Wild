<#
.SYNOPSIS
    Automated setup script for Godot AI MCP plugin (hi-godot/godot-ai) in Godot 4.
.DESCRIPTION
    1. Queries GitHub API for the latest release of hi-godot/godot-ai (or uses specified version).
    2. Downloads and extracts godot-ai-v4-plugin.zip into addons/godot_ai.
    3. Enables the plugin in project.godot under [editor_plugins].
    4. Configures the user's Antigravity MCP config (~/.gemini/config/mcp_config.json) to attach via uvx.
    5. Runs a headless Godot check to verify clean plugin compilation.
#>
param (
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path "$PSScriptRoot\..\..\..\.."
Write-Host "Setting up Godot AI MCP in project root: $ProjectRoot" -ForegroundColor Cyan

# 1. Determine release version & download URL
if (-not $Version) {
    Write-Host "Fetching latest release from GitHub API..."
    $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/hi-godot/godot-ai/releases/latest" -Headers @{"User-Agent"="Godot-MCP-Setup"}
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

# 2. Download and extract
$TempZip = Join-Path $env:TEMP "godot-ai-plugin-$Version.zip"
$TempExtract = Join-Path $env:TEMP "godot-ai-extract-$Version"

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

Write-Host "Installing to $TargetAddon..."
Copy-Item -Path $SourceAddon -Destination $TargetAddon -Recurse -Force

# 3. Enable plugin in project.godot
$ProjectGodot = Join-Path $ProjectRoot "project.godot"
if (Test-Path $ProjectGodot) {
    $Content = Get-Content $ProjectGodot -Raw
    if ($Content -notmatch "res://addons/godot_ai/plugin\.cfg") {
        Write-Host "Registering plugin in project.godot..." -ForegroundColor Cyan
        if ($Content -match "\[editor_plugins\]") {
            $Content = $Content -replace "\[editor_plugins\]\r?\n(\r?\nenabled=PackedStringArray\()?", "[editor_plugins]`n`nenabled=PackedStringArray(`"res://addons/godot_ai/plugin.cfg`", "
        } else {
            $PluginSection = "`n[editor_plugins]`n`nenabled=PackedStringArray(`"res://addons/godot_ai/plugin.cfg`")`n"
            $Content = $Content -replace "(\[autoload\])", "$PluginSection`$1"
        }
        Set-Content -Path $ProjectGodot -Value $Content -NoNewline
    }
}

# 4. Update MCP Client configs (~/.gemini/config/mcp_config.json and ~/.gemini/antigravity/mcp_config.json)
$McpConfigPaths = @(
    (Join-Path $env:USERPROFILE ".gemini\config\mcp_config.json"),
    (Join-Path $env:USERPROFILE ".gemini\antigravity\mcp_config.json")
)

foreach ($McpPath in $McpConfigPaths) {
    if (Test-Path $McpPath) {
        Write-Host "Configuring MCP server entry in $McpPath..." -ForegroundColor Cyan
        $Json = Get-Content $McpPath -Raw | ConvertFrom-Json
        if (-not $Json.mcpServers) {
            $Json | Add-Member -MemberType NoteProperty -Name "mcpServers" -Value ([PSCustomObject]@{})
        }
        $GodotServer = [PSCustomObject]@{
            command = "uvx"
            args = @(
                "--from",
                "godot-ai==$Version",
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
        $Json | ConvertTo-Json -Depth 10 | Set-Content $McpPath
    }
}

# 5. Verification check
$GodotExe = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if (Test-Path $GodotExe) {
    Write-Host "Running headless verification with Godot..." -ForegroundColor Green
    & $GodotExe --headless --path "$ProjectRoot" --quit
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Headless verification succeeded! Godot AI MCP is ready." -ForegroundColor Green
    } else {
        Write-Warning "Headless exit code: $LASTEXITCODE"
    }
}

Write-Host "Setup complete!" -ForegroundColor Green
