#Requires -Version 5.1

<#
.SYNOPSIS
  Installs the Windows equivalent of the minimal macOS terminal setup.

.DESCRIPTION
  Installs Windows Terminal, PowerShell 7, Git, Starship, Atuin, a JetBrains
  Mono Nerd Font and Node.js LTS with WinGet. It then installs the tracked
  PowerShell, Starship, Atuin and Windows Terminal configuration.

  Existing configuration is copied to
  ~/.config-backups/dotfiles-<timestamp>/ before it is replaced. Codex
  configuration and credentials are never read, copied or changed.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
#>

[CmdletBinding()]
param(
    [switch]$SkipCodex
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$ScriptDirectory = $PSScriptRoot
$ConfigDirectory = Join-Path $ScriptDirectory 'config'
$BackupStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDirectory = Join-Path $HOME ".config-backups\dotfiles-$BackupStamp"

function Write-Info {
    param([string]$Message)
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "OK  $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param([string]$Message)
    Write-Host "!   $Message" -ForegroundColor Yellow
}

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Update-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pathEntries = (@($env:Path, $machinePath, $userPath) -join ';') -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    $env:Path = $pathEntries -join ';'
}

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [string]$DisplayName,

        [string]$Command
    )

    if ($Command -and (Test-Command $Command)) {
        Write-Success "$DisplayName already installed."
        return
    }

    $installedPackages = & winget list --id $Id --exact --accept-source-agreements 2>$null | Out-String
    if ($LASTEXITCODE -eq 0 -and $installedPackages -match [regex]::Escape($Id)) {
        Update-SessionPath
        Write-Success "$DisplayName already installed."
        return
    }

    Write-Info "Installing $DisplayName..."
    & winget install --id $Id --exact --silent --source winget `
        --accept-source-agreements --accept-package-agreements

    if ($LASTEXITCODE -ne 0) {
        throw "WinGet could not install $DisplayName ($Id). Exit code: $LASTEXITCODE"
    }

    Update-SessionPath
    Write-Success "$DisplayName installed."
}

function Install-Config {
    param(
        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Target
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Missing config asset: $Source"
    }

    if (Test-Path -LiteralPath $Target) {
        $targetRoot = [IO.Path]::GetPathRoot($Target)
        $relativeTarget = $Target.Substring($targetRoot.Length).TrimStart('\', '/')
        $backupTarget = Join-Path $BackupDirectory $relativeTarget
        $backupParent = Split-Path -Parent $backupTarget

        New-Item -ItemType Directory -Path $backupParent -Force | Out-Null
        Copy-Item -LiteralPath $Target -Destination $backupTarget -Force
        Write-Success "Backed up $Target"
    }

    $targetParent = Split-Path -Parent $Target
    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Target -Force
    Write-Success "Installed $Target"
}

Write-Host ''
Write-Host 'Windows Dev Terminal Setup' -ForegroundColor White
Write-Host '--------------------------'
Write-Host ''

if (-not $IsWindows -and $PSVersionTable.PSVersion.Major -ge 6) {
    throw 'This setup script must be run on Windows.'
}

if (-not (Test-Command winget)) {
    throw 'WinGet is required. Install or update App Installer from the Microsoft Store, then run this script again.'
}

# Core terminal tools.
Install-WinGetPackage -Id 'Microsoft.WindowsTerminal' -DisplayName 'Windows Terminal' -Command 'wt.exe'
Install-WinGetPackage -Id 'Microsoft.PowerShell' -DisplayName 'PowerShell 7' -Command 'pwsh.exe'
Install-WinGetPackage -Id 'Git.Git' -DisplayName 'Git' -Command 'git.exe'
Install-WinGetPackage -Id 'Starship.Starship' -DisplayName 'Starship' -Command 'starship.exe'
Install-WinGetPackage -Id 'Atuinsh.Atuin' -DisplayName 'Atuin' -Command 'atuin.exe'

$fontLocations = @(
    (Join-Path $env:WINDIR 'Fonts')
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')
)
$hasJetBrainsNerdFont = $fontLocations | ForEach-Object {
    Get-ChildItem -LiteralPath $_ -Filter 'JetBrainsMono*NerdFont*' -ErrorAction SilentlyContinue
} | Select-Object -First 1

if ($hasJetBrainsNerdFont) {
    Write-Success 'JetBrains Mono Nerd Font already installed.'
} else {
    Install-WinGetPackage -Id 'DEVCOM.JetBrainsMonoNerdFont' -DisplayName 'JetBrains Mono Nerd Font'
}

if (-not (Test-Command node.exe) -or -not (Test-Command npm.cmd)) {
    Install-WinGetPackage -Id 'OpenJS.NodeJS.LTS' -DisplayName 'Node.js LTS'
}

Update-SessionPath

# PowerShell 7 keeps its profile under the user's redirected Documents folder.
$documentsDirectory = [Environment]::GetFolderPath('MyDocuments')
$powerShellProfile = Join-Path $documentsDirectory 'PowerShell\Microsoft.PowerShell_profile.ps1'
$terminalFragment = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\eddie-dotfiles\developer.json'

Write-Info 'Installing terminal configuration...'
Install-Config `
    -Source (Join-Path $ConfigDirectory 'Microsoft.PowerShell_profile.ps1') `
    -Target $powerShellProfile
Install-Config `
    -Source (Join-Path $ConfigDirectory 'starship.toml') `
    -Target (Join-Path $HOME '.config\starship.toml')
Install-Config `
    -Source (Join-Path $ConfigDirectory 'atuin.toml') `
    -Target (Join-Path $HOME '.config\atuin\config.toml')
Install-Config `
    -Source (Join-Path $ConfigDirectory 'windows-terminal.fragment.json') `
    -Target $terminalFragment

if (-not $SkipCodex) {
    if (Test-Command codex) {
        Write-Success 'Codex CLI already installed.'
    } elseif ((Test-Command node.exe) -and (Test-Command npm.cmd)) {
        Write-Info 'Installing Codex CLI with npm...'
        & npm.cmd install --global '@openai/codex'
        if ($LASTEXITCODE -ne 0) {
            throw "npm could not install Codex CLI. Exit code: $LASTEXITCODE"
        }
        Update-SessionPath
        Write-Success 'Codex CLI installed.'
    } else {
        Write-WarningMessage 'Codex CLI was not installed because Node.js and npm are not available in this session.'
        Write-WarningMessage 'Restart PowerShell and run: npm install --global @openai/codex'
    }
}

Write-Host ''
Write-Success 'Windows terminal setup complete.'
Write-Host ''
Write-Host 'Next:'
Write-Host '  1. Close and reopen Windows Terminal.'
Write-Host '  2. Open the "Developer PowerShell" profile from the new-tab menu.'
Write-Host '  3. Optionally make it the default under Settings > Startup.'
Write-Host '  4. Run "codex login" to connect your ChatGPT account.'
Write-Host '  5. Run "atuin login" if you want history sync.'
if (Test-Path -LiteralPath $BackupDirectory) {
    Write-Host "Backups: $BackupDirectory"
}
