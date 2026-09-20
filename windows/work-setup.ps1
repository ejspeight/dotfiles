#Requires -Version 5.1

<#
.SYNOPSIS
  Corporate-friendly Windows terminal setup: Windows Terminal, PowerShell 7,
  Starship and TLS trust plumbing for a TLS-inspecting proxy such as Zscaler.

.DESCRIPTION
  Written for a managed client machine where the toolchain (Node, Docker,
  Neovim, .NET) is already installed and the main friction is TLS inspection.

  It does four things, each independently skippable:

    1. Installs only terminal components: Windows Terminal, PowerShell 7,
       Starship, Atuin and a Nerd Font. Never languages, runtimes or SDKs.
    2. Detects the corporate TLS-inspection root CA, exports PEM bundles and
       points the tools that carry their own CA store at them.
    3. Writes a PowerShell profile, a Starship prompt, an Atuin config and a
       Windows Terminal fragment.
    4. Sets up a private local LLM: Ollama, the llm CLI and a model built for
       terminal use. Nothing leaves the machine and no account is needed.

  Every install is per-user and needs no administrator rights. Where WinGet
  cannot provide a package, the script falls back to the vendor's own release
  archive unpacked into ~/.local/bin.

  The file is deliberately pure ASCII and saved with a UTF-8 BOM. Windows
  PowerShell 5.1 reads a BOM-less script as the ANSI codepage, which would
  corrupt every prompt glyph it writes out.

  TLS verification is never disabled. The script only teaches tools to trust
  the same roots Windows already trusts, which is the supported way to work
  behind an inspecting proxy.

  It is safe to re-run. Existing files are backed up to
  ~/.config-backups/dotfiles-<timestamp>/ before replacement, and the Windows
  Terminal fragment adds a profile without rewriting settings.json.

.PARAMETER SkipInstalls
  Skip all WinGet installs and only apply certificates and configuration.

.PARAMETER SkipCerts
  Skip certificate detection and environment variables.

.PARAMETER SkipConfig
  Skip the PowerShell profile, Starship config, Atuin config and Windows
  Terminal fragment.

.PARAMETER SkipLlm
  Skip the local LLM setup (Ollama, llm CLI and model download).

.PARAMETER LlmModel
  Ollama model tag to build terminal-llm from, instead of the default.
  Example: -LlmModel 'gemma4:12b'

.PARAMETER ExtraCaSubject
  Additional root CA subject patterns to treat as corporate, for proxies not
  covered by the built-in list. Example: -ExtraCaSubject 'Contoso Internal CA'

.PARAMETER ProbeHost
  Hosts to TLS-probe to discover the root CA actually terminating connections.

.PARAMETER RemoveCertEnv
  Undo: remove the certificate environment variables this script sets, then
  exit. Use this if the bundles ever cause trouble.

.EXAMPLE
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\work-setup.ps1

.EXAMPLE
  # Certificates and config only, no installs (locked-down machine).
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\work-setup.ps1 -SkipInstalls

.EXAMPLE
  # Roll back the certificate environment variables.
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\work-setup.ps1 -RemoveCertEnv
#>

[CmdletBinding()]
param(
    [switch]$SkipInstalls,
    [switch]$SkipCerts,
    [switch]$SkipConfig,
    [switch]$SkipLlm,
    [string]$LlmModel = '',
    [string[]]$ExtraCaSubject = @(),
    [string[]]$ProbeHost = @(
        'registry.npmjs.org',
        'github.com',
        'raw.githubusercontent.com',
        'api.nuget.org',
        'login.microsoftonline.com',
        'management.azure.com',
        'mcr.microsoft.com',
        'pypi.org'
    ),
    [switch]$RemoveCertEnv
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# PowerShell 7.4+ turns a non-zero native exit code into a terminating error
# while $ErrorActionPreference is 'Stop'. This script inspects exit codes
# itself so it can degrade gracefully, so opt out where the setting exists.
if (Test-Path Variable:\PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

# -- Paths ---------------------------------------------------------------------

$BackupStamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$BackupDirectory = Join-Path $HOME ".config-backups\dotfiles-$BackupStamp"
$CertDirectory   = Join-Path $HOME '.config\certs'
$CorporateRoots  = Join-Path $CertDirectory 'corporate-roots.pem'
$WindowsBundle   = Join-Path $CertDirectory 'windows-ca-bundle.pem'

# Environment variables this script owns, so -RemoveCertEnv can undo them.
$CertEnvNames = @(
    'NODE_EXTRA_CA_CERTS',
    'REQUESTS_CA_BUNDLE',
    'SSL_CERT_FILE',
    'CURL_CA_BUNDLE',
    'PIP_CERT'
)

# Per-user fallbacks for packages WinGet cannot provide. Both are plain HTTPS
# to github.com, verified against the Windows trust store like any other
# download; nothing here weakens certificate checking.
$AtuinReleaseUrl = 'https://github.com/atuinsh/atuin/releases/latest/download/atuin-x86_64-pc-windows-msvc.zip'

# WinGet fetches Ollama's installer from ollama.com, which an inspecting proxy
# may refuse outright (HTTP 403). This archive is the same build, served from
# github.com, and unpacks without an installer. It is around 1.5GB.
$OllamaReleaseUrl = 'https://github.com/ollama/ollama/releases/latest/download/ollama-windows-amd64.zip'

# Pinned first so a new upstream release cannot change what gets installed,
# with the moving URL as a fallback if the tag is ever withdrawn.
$NerdFontUrls = @(
    'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/JetBrainsMono.zip',
    'https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip'
)

# Root CA subjects belonging to common enterprise TLS-inspection appliances.
$InspectionPatterns = @(
    'Zscaler',
    'Netskope',
    'Palo Alto',
    'Blue Coat',
    'Broadcom',
    'Symantec Web',
    'Forcepoint',
    'McAfee Web',
    'Fortinet',
    'FortiGate',
    'Cisco Umbrella',
    'Sophos',
    'Menlo Security',
    'Trend Micro',
    'iboss'
) + $ExtraCaSubject

# -- Output helpers ------------------------------------------------------------

function Write-Section {
    param([string]$Message)
    Write-Host ''
    Write-Host "== $Message" -ForegroundColor White
}

function Write-Info    { param([string]$Message) Write-Host "   $Message" -ForegroundColor Cyan }
function Write-Ok      { param([string]$Message) Write-Host "OK $Message" -ForegroundColor Green }
function Write-Warn    { param([string]$Message) Write-Host " ! $Message" -ForegroundColor Yellow }
function Write-Detail  { param([string]$Message) Write-Host "   $Message" -ForegroundColor DarkGray }

function Test-Command {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-Administrator {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Native {
    <#
      Runs an external command and returns its exit code. Windows PowerShell
      turns redirected native stderr into a terminating error while
      $ErrorActionPreference is 'Stop', so it is relaxed for the call.
    #>
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $ErrorActionPreference = 'Continue'
    try {
        $output = & $FilePath @ArgumentList 2>&1 | Out-String
        if ($output) { Write-Verbose $output }
        return $LASTEXITCODE
    } catch {
        Write-Verbose "$FilePath failed: $($_.Exception.Message)"
        return 1
    }
}

function Update-SessionPath {
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries = (@($env:Path, $machinePath, $userPath) -join ';') -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
    $env:Path = $entries -join ';'
}

function Add-UserPathEntry {
    # Adds a directory to the persistent user PATH as well as this session.
    # Tools installed into ~/.local/bin are useless until the next shell
    # otherwise.
    param([Parameter(Mandatory)][string]$Directory)

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $entries  = @($userPath -split ';' | Where-Object { $_ })
    if ($entries -notcontains $Directory) {
        [Environment]::SetEnvironmentVariable('Path', (@($entries + $Directory) -join ';'), 'User')
        Write-Detail "added $Directory to the user PATH"
    }
    if (($env:Path -split ';') -notcontains $Directory) {
        $env:Path = "$Directory;$env:Path"
    }
}

function Install-FromGitHubZip {
    <#
      Per-user fallback for a package WinGet cannot supply: download a release
      archive and drop one executable into ~/.local/bin. No administrator
      rights and no Microsoft Store involved.
    #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$ExeName,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $binDirectory = Join-Path $HOME '.local\bin'
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-' + [Guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Path $binDirectory -Force | Out-Null
        New-Item -ItemType Directory -Path $temp -Force | Out-Null

        $archive = Join-Path $temp 'download.zip'
        Write-Detail "downloading $Url"
        Invoke-WebRequest -Uri $Url -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath $temp -Force

        $exe = Get-ChildItem -LiteralPath $temp -Recurse -Filter $ExeName -File |
            Select-Object -First 1
        if (-not $exe) {
            Write-Warn "The $DisplayName archive did not contain $ExeName."
            return $false
        }

        Copy-Item -LiteralPath $exe.FullName -Destination (Join-Path $binDirectory $ExeName) -Force
        Add-UserPathEntry -Directory $binDirectory
        Write-Ok "$DisplayName installed to $binDirectory."
        return $true
    } catch {
        Write-Warn "Could not install $DisplayName from its release archive: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-ArchiveToLocal {
    <#
      Per-user fallback for a tool that needs more than a single executable:
      unpack a whole release archive under ~/.local and put the directory
      holding its executable on PATH. No administrator rights, no installer.
    #>
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ExeName,
        [Parameter(Mandatory)][string]$DisplayName
    )

    $destination = Join-Path $HOME ".local\$Name"
    $existing = if (Test-Path -LiteralPath $destination) {
        Get-ChildItem -LiteralPath $destination -Recurse -Filter $ExeName -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
    }
    if ($existing) {
        Add-UserPathEntry -Directory $existing.DirectoryName
        Write-Ok "$DisplayName already unpacked in $destination."
        return $true
    }

    $temp = Join-Path ([IO.Path]::GetTempPath()) ('dotfiles-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        New-Item -ItemType Directory -Path $destination -Force | Out-Null

        $archive = Join-Path $temp 'download.zip'
        Write-Detail "downloading $Url"
        Write-Detail 'this is a large archive, so it stays quiet for a while'
        Invoke-WebRequest -Uri $Url -OutFile $archive -UseBasicParsing
        Expand-Archive -LiteralPath $archive -DestinationPath $destination -Force

        $exe = Get-ChildItem -LiteralPath $destination -Recurse -Filter $ExeName -File |
            Select-Object -First 1
        if (-not $exe) {
            Write-Warn "The $DisplayName archive did not contain $ExeName."
            return $false
        }

        Add-UserPathEntry -Directory $exe.DirectoryName
        Write-Ok "$DisplayName unpacked into $destination."
        return $true
    } catch {
        Write-Warn "Could not install $DisplayName from its release archive: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Write-TextFile {
    # Writes UTF-8 without a BOM. Windows Terminal and Starship both parse
    # their files more reliably without one.
    param([string]$Path, [string]$Content)

    $parent = Split-Path -Parent $Path
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    [IO.File]::WriteAllText($Path, $Content, (New-Object Text.UTF8Encoding($false)))
}

function Backup-ExistingFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return }

    $root     = [IO.Path]::GetPathRoot($Path)
    $relative = $Path.Substring($root.Length).TrimStart('\', '/')
    $target   = Join-Path $BackupDirectory $relative

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $Path -Destination $target -Force
    Write-Detail "backed up $Path"
}

function Install-Config {
    param([string]$Path, [string]$Content)

    Backup-ExistingFile -Path $Path
    Write-TextFile -Path $Path -Content $Content
    Write-Ok "wrote $Path"
}

# -- Undo path -----------------------------------------------------------------

if ($RemoveCertEnv) {
    Write-Section 'Removing certificate environment variables'
    foreach ($name in $CertEnvNames) {
        $current = [Environment]::GetEnvironmentVariable($name, 'User')
        if ($current) {
            [Environment]::SetEnvironmentVariable($name, $null, 'User')
            Write-Ok "removed $name (was $current)"
        } else {
            Write-Detail "$name was not set"
        }
        Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
    }
    Write-Host ''
    Write-Info 'Git was left as-is. To revert the TLS backend:'
    Write-Detail '  git config --global --unset http.sslBackend'
    Write-Host ''
    Write-Detail "PEM bundles remain at $CertDirectory and can be deleted."
    return
}

# -- Preflight -----------------------------------------------------------------

Write-Host ''
Write-Host 'Windows Work Terminal Setup' -ForegroundColor White
Write-Host '---------------------------'

if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    throw 'This script must run on Windows.'
}

$IsAdmin = Test-Administrator
$Scope   = if ($IsAdmin) { 'machine' } else { 'user' }
Write-Detail "Running as $(if ($IsAdmin) { 'administrator' } else { 'standard user' }); WinGet scope: $Scope"

# -- 1. Terminal components ----------------------------------------------------

function Install-WinGetPackage {
    param(
        [Parameter(Mandatory)][string]$Id,
        [Parameter(Mandatory)][string]$DisplayName,
        [string]$Command
    )

    if ($Command -and (Test-Command $Command)) {
        Write-Ok "$DisplayName already present."
        return $true
    }

    Write-Info "Installing $DisplayName..."
    # --source winget avoids the Microsoft Store source, which is commonly
    # disabled by policy on managed machines.
    $baseArguments = @(
        'install', '--id', $Id, '--exact', '--silent', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements',
        '--disable-interactivity'
    )

    $exitCode = Invoke-Native -FilePath 'winget' -ArgumentList ($baseArguments + @('--scope', $Scope))

    # Retry at user scope; machine scope needs an elevated WinGet context that
    # some managed machines refuse even for a local administrator.
    if ($exitCode -ne 0 -and $Scope -eq 'machine') {
        Write-Detail 'machine scope failed, retrying at user scope'
        $exitCode = Invoke-Native -FilePath 'winget' -ArgumentList ($baseArguments + @('--scope', 'user'))
    }

    if ($exitCode -ne 0) {
        Write-Warn "WinGet could not install $DisplayName ($Id). Exit code $exitCode."
        Write-Detail 'Install it manually, then re-run this script.'
        return $false
    }

    Update-SessionPath
    Write-Ok "$DisplayName installed."
    return $true
}

function Get-InstalledFontNames {
    $hives = @(
        'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts',
        'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    )
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($hive in $hives) {
        if (-not (Test-Path $hive)) { continue }
        $item = Get-ItemProperty -Path $hive -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -like 'PS*') { continue }
            $names.Add($property.Name)
        }
    }
    return $names
}

function ConvertTo-FontFamilyName {
    # The registry lists one entry per weight, for example
    # "JetBrainsMono Nerd Font Mono Bold (TrueType)". Windows Terminal wants
    # the family, so drop the format and weight suffixes.
    param([string]$RegistryName)

    $name = $RegistryName -replace '\s*\((TrueType|OpenType)\)\s*$', ''
    $name = $name -replace '\s+(Thin|ExtraLight|Light|Regular|Medium|SemiBold|Bold|ExtraBold|Black)(\s+Italic)?$', ''
    $name = $name -replace '\s+Italic$', ''
    return $name.Trim()
}

function Resolve-TerminalFont {
    <#
      The best Nerd Font already on the machine, or $null if there is none.

      -PreferredOnly narrows it to JetBrainsMono, the face the macOS setup uses.
      Windows ships Cascadia Mono NF, which is a perfectly good Nerd Font, so
      without this the script would always find one and never install the face
      that was actually asked for.
    #>
    param([switch]$PreferredOnly)

    $preferences = @(
        @{ Face = 'JetBrainsMono Nerd Font'; Match = 'JetBrainsMono*Nerd Font*'; Preferred = $true },
        @{ Face = 'CaskaydiaCove Nerd Font'; Match = 'CaskaydiaCove*Nerd Font*'; Preferred = $false },
        @{ Face = 'Cascadia Mono NF';        Match = 'Cascadia Mono NF*';        Preferred = $false },
        @{ Face = 'Cascadia Code NF';        Match = 'Cascadia Code NF*';        Preferred = $false },
        @{ Face = $null;                     Match = '*Nerd Font*';              Preferred = $false }
    )

    $installed = Get-InstalledFontNames
    foreach ($preference in $preferences) {
        if ($PreferredOnly -and -not $preference.Preferred) { continue }
        foreach ($name in $installed) {
            if ($name -like $preference.Match) {
                if ($preference.Face) { return $preference.Face }
                return (ConvertTo-FontFamilyName $name)
            }
        }
    }
    return $null
}

function Write-FontDiagnostics {
    # Bug reports about missing glyphs are almost always "the font is not
    # actually registered", so say plainly what is there.
    $hives = [ordered]@{
        'machine (HKLM)' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
        'user (HKCU)'    = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    }
    foreach ($label in $hives.Keys) {
        $matched = @()
        $item = Get-ItemProperty -Path $hives[$label] -ErrorAction SilentlyContinue
        if ($item) {
            $matched = @($item.PSObject.Properties |
                Where-Object { $_.Name -notlike 'PS*' -and ($_.Name -like '*Nerd*' -or $_.Name -like '*JetBrains*' -or $_.Name -like '*Cascadia*') } |
                ForEach-Object { $_.Name })
        }
        if ($matched.Count -gt 0) {
            Write-Detail "$label : $($matched.Count) candidate font entries, e.g. $($matched[0])"
        } else {
            Write-Detail "$label : no Nerd Font or Cascadia entries"
        }
    }
}

function Install-NerdFontPerUser {
    <#
      Installs JetBrainsMono Nerd Font for this user only, which needs no
      administrator rights: the files go in the per-user font directory and are
      registered under HKCU. Applications started afterwards can use them.

      Used when WinGet cannot install the font, which is the normal case on a
      managed machine because the package is machine-scope.
    #>
    $fontDirectory = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
    $registryKey   = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    $temp          = Join-Path ([IO.Path]::GetTempPath()) ('nerdfont-' + [Guid]::NewGuid().ToString('N'))
    $archive       = Join-Path $temp 'JetBrainsMono.zip'

    # Face name suffix per file, following the usual registry convention.
    $faces = [ordered]@{
        'Regular'    = ''
        'Bold'       = ' Bold'
        'Italic'     = ' Italic'
        'BoldItalic' = ' Bold Italic'
    }

    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        New-Item -ItemType Directory -Path $fontDirectory -Force | Out-Null
        if (-not (Test-Path $registryKey)) { New-Item -Path $registryKey -Force | Out-Null }

        $downloaded = $false
        foreach ($url in $NerdFontUrls) {
            try {
                Write-Detail "downloading $url"
                Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
                $downloaded = $true
                break
            } catch {
                Write-Detail "download failed: $($_.Exception.Message)"
            }
        }
        if (-not $downloaded) {
            Write-Warn 'Could not download the Nerd Font archive.'
            return $false
        }

        # Extract only the four faces needed. The archive carries well over a
        # hundred, and unpacking all of them is slow for no benefit.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($archive)
        $installed = 0
        try {
            foreach ($style in $faces.Keys) {
                # Each face is handled on its own: Windows locks a font file
                # while it is loaded, and one locked face must not stop the rest.
                try {
                    # The trailing hyphen keeps the NerdFontMono and NerdFontPropo
                    # variants out; this is the proportional-spacing family that
                    # the terminal fragment names.
                    $wanted = "JetBrainsMonoNerdFont-$style.ttf"
                    $entry = $zip.Entries | Where-Object { $_.Name -eq $wanted } | Select-Object -First 1
                    if (-not $entry) { continue }

                    # A complete file left by an earlier run is already what we
                    # want, and may well be locked. Keep it and just register it.
                    $target = Join-Path $fontDirectory $entry.Name
                    $alreadyThere = (Test-Path -LiteralPath $target) -and
                                    ((Get-Item -LiteralPath $target).Length -eq $entry.Length)
                    if ($alreadyThere) {
                        Write-Detail "$style : already on disk, registering it"
                    } else {
                        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
                    }

                    # A per-user entry holds the full path; HKLM entries hold
                    # only the file name. The label has to contain both
                    # "JetBrainsMono" and "Nerd Font" or Resolve-TerminalFont
                    # will not match it.
                    New-ItemProperty -Path $registryKey -Name "JetBrainsMono Nerd Font$($faces[$style]) (TrueType)" `
                        -Value $target -PropertyType String -Force | Out-Null
                    $installed++
                } catch {
                    Write-Detail "$style : $($_.Exception.Message)"
                }
            }
        } finally {
            $zip.Dispose()
        }

        if ($installed -eq 0) {
            Write-Warn 'The Nerd Font archive held none of the expected faces.'
            return $false
        }

        Write-Ok "Installed $installed JetBrainsMono Nerd Font face(s) for this user."
        Write-Detail "fonts  $fontDirectory"
        return $true
    } catch {
        Write-Warn "Per-user font install failed: $($_.Exception.Message)"
        return $false
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Resolve-FallbackFont {
    # No Nerd Font is available, so pick a monospace face that is definitely
    # registered. Naming a font that is not installed makes Windows Terminal
    # warn on every launch, which is worse than missing glyphs.
    $installed = Get-InstalledFontNames
    foreach ($candidate in @('Cascadia Mono', 'Cascadia Code', 'Consolas')) {
        foreach ($name in $installed) {
            if ($name -like "$candidate*") { return $candidate }
        }
    }
    # Present on every Windows install since Vista.
    return 'Consolas'
}

if (-not $SkipInstalls) {
    Write-Section 'Terminal components'

    $hasWinGet = Test-Command winget
    if (-not $hasWinGet) {
        Write-Warn 'WinGet is unavailable. Using per-user fallbacks where one exists.'
        Write-Detail 'Install "App Installer" from the Microsoft Store, or ask IT, then re-run.'
    } else {
        Install-WinGetPackage -Id 'Microsoft.WindowsTerminal' -DisplayName 'Windows Terminal' -Command 'wt.exe'  | Out-Null
        Install-WinGetPackage -Id 'Microsoft.PowerShell'      -DisplayName 'PowerShell 7'     -Command 'pwsh.exe' | Out-Null
        Install-WinGetPackage -Id 'Starship.Starship'         -DisplayName 'Starship'         -Command 'starship.exe' | Out-Null
    }

    # Atuin: the same searchable history as macOS. WinGet publishes it as
    # Atuinsh.Atuin; the release archive is the fallback.
    if (Test-Command atuin) {
        Write-Ok 'Atuin already present.'
    } else {
        $atuinInstalled = $false
        if ($hasWinGet) {
            $atuinInstalled = Install-WinGetPackage -Id 'Atuinsh.Atuin' -DisplayName 'Atuin' -Command 'atuin.exe'
        }
        if (-not $atuinInstalled) {
            Install-FromGitHubZip -Url $AtuinReleaseUrl -ExeName 'atuin.exe' -DisplayName 'Atuin' | Out-Null
        }
    }

    # Font. WinGet's package is machine-scope and usually refused on a managed
    # machine, so fall through to the per-user install rather than giving up:
    # without a Nerd Font every prompt icon renders as a box.
    Write-Info 'Checking for a Nerd Font...'
    Write-FontDiagnostics
    if (Resolve-TerminalFont -PreferredOnly) {
        Write-Ok 'JetBrainsMono Nerd Font already present.'
    } else {
        $alternative = Resolve-TerminalFont
        if ($alternative) {
            Write-Detail "only $alternative is installed; fetching JetBrainsMono to match the macOS setup"
        }
        if ($hasWinGet) {
            Install-WinGetPackage -Id 'DEVCOM.JetBrainsMonoNerdFont' -DisplayName 'JetBrains Mono Nerd Font' | Out-Null
        }
        # The WinGet package installs machine-wide, so a managed device normally
        # refuses it. Fall through to the per-user install rather than settling.
        if (-not (Resolve-TerminalFont -PreferredOnly)) {
            Write-Detail 'installing JetBrainsMono Nerd Font for this user'
            if (-not (Install-NerdFontPerUser) -and $alternative) {
                Write-Detail "keeping $alternative, which already renders prompt glyphs"
            }
        }
    }

    Update-SessionPath
}

# -- 2. Corporate TLS trust ----------------------------------------------------

function ConvertTo-Pem {
    param([Security.Cryptography.X509Certificates.X509Certificate2]$Certificate)

    $base64 = [Convert]::ToBase64String(
        $Certificate.RawData,
        [Base64FormattingOptions]::InsertLineBreaks)

    $builder = New-Object Text.StringBuilder
    [void]$builder.AppendLine("# Subject: $($Certificate.Subject)")
    [void]$builder.AppendLine("# Thumbprint: $($Certificate.Thumbprint)")
    [void]$builder.AppendLine('-----BEGIN CERTIFICATE-----')
    [void]$builder.AppendLine($base64)
    [void]$builder.AppendLine('-----END CERTIFICATE-----')
    return $builder.ToString()
}

function Get-TrustedRootCertificate {
    # Reading the root stores does not require administrator rights.
    $stores = @('Cert:\LocalMachine\Root', 'Cert:\CurrentUser\Root')
    $found = @()
    foreach ($store in $stores) {
        $certs = Get-ChildItem -Path $store -ErrorAction SilentlyContinue
        if ($certs) { $found += $certs }
    }
    return $found | Where-Object { $_.NotAfter -gt (Get-Date) }
}

function Get-ChainRootCertificate {
    <#
      Opens a TLS handshake and inspects which root CA signs the presented
      chain. Behind an inspecting proxy this is the proxy's root, which is
      exactly the certificate the tools below need to trust.

      The validation callback returns true because this handshake exists only
      to read the chain. No request is sent and the connection is closed
      immediately.
    #>
    param([string]$HostName, [int]$TimeoutMilliseconds = 5000)

    $client = $null
    $stream = $null
    try {
        $client = New-Object Net.Sockets.TcpClient
        $connect = $client.BeginConnect($HostName, 443, $null, $null)
        if (-not $connect.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) { return $null }
        $client.EndConnect($connect)

        $callback = [Net.Security.RemoteCertificateValidationCallback] { param($s, $c, $ch, $e) return $true }
        $stream = New-Object Net.Security.SslStream($client.GetStream(), $false, $callback)
        $stream.AuthenticateAsClient($HostName)

        if (-not $stream.RemoteCertificate) { return $null }
        $leaf = New-Object Security.Cryptography.X509Certificates.X509Certificate2($stream.RemoteCertificate)

        $chain = New-Object Security.Cryptography.X509Certificates.X509Chain
        $chain.ChainPolicy.RevocationMode = 'NoCheck'
        [void]$chain.Build($leaf)

        if ($chain.ChainElements.Count -eq 0) { return $null }
        return $chain.ChainElements[$chain.ChainElements.Count - 1].Certificate
    } catch {
        return $null
    } finally {
        if ($stream) { $stream.Dispose() }
        if ($client) { $client.Close() }
    }
}

if (-not $SkipCerts) {
    Write-Section 'Corporate TLS trust'

    [Net.ServicePointManager]::SecurityProtocol =
        [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11

    $allRoots  = Get-TrustedRootCertificate
    $corporate = @{}   # thumbprint -> certificate
    $inspected = @()   # hosts observed being intercepted

    # a. Roots whose subject matches a known inspection appliance.
    foreach ($cert in $allRoots) {
        foreach ($pattern in $InspectionPatterns) {
            if ($cert.Subject -like "*$pattern*") {
                $corporate[$cert.Thumbprint] = $cert
                break
            }
        }
    }

    # b. Roots actually terminating connections to the hosts your tooling uses.
    Write-Info "Probing $($ProbeHost.Count) hosts to find the terminating root CA..."
    foreach ($name in $ProbeHost) {
        $root = Get-ChainRootCertificate -HostName $name
        if (-not $root) {
            Write-Detail "$name : unreachable, skipped"
            continue
        }

        $isInspection = $false
        foreach ($pattern in $InspectionPatterns) {
            if ($root.Subject -like "*$pattern*") { $isInspection = $true; break }
        }

        if ($isInspection) {
            $inspected += $name
            $corporate[$root.Thumbprint] = $root
            Write-Detail "$name : inspected"
        } else {
            Write-Detail "$name : direct"
        }
    }

    if ($corporate.Count -eq 0) {
        Write-Ok 'No TLS inspection detected. Writing the Windows trust bundle anyway for portability.'
    } else {
        Write-Ok "Found $($corporate.Count) corporate root CA(s):"
        foreach ($cert in $corporate.Values) {
            Write-Detail "  $($cert.Subject)"
        }
        if ($inspected.Count -gt 0) {
            Write-Detail "  intercepting: $($inspected -join ', ')"
        }
    }

    New-Item -ItemType Directory -Path $CertDirectory -Force | Out-Null

    # corporate-roots.pem holds only the extra roots. It is used with
    # NODE_EXTRA_CA_CERTS, which ADDS to Node's built-in trust store.
    $corporatePem = New-Object Text.StringBuilder
    [void]$corporatePem.AppendLine('# Corporate root CAs detected on this machine.')
    [void]$corporatePem.AppendLine("# Generated $(Get-Date -Format 'u') by work-setup.ps1. Re-run to refresh.")
    foreach ($cert in $corporate.Values) {
        [void]$corporatePem.AppendLine((ConvertTo-Pem -Certificate $cert))
    }
    Write-TextFile -Path $CorporateRoots -Content $corporatePem.ToString()
    Write-Ok "wrote $CorporateRoots"

    # windows-ca-bundle.pem is the FULL Windows trust store. It is used with
    # the variables that REPLACE a tool's bundle, so it must be complete or
    # non-inspected connections would break.
    $bundlePem = New-Object Text.StringBuilder
    [void]$bundlePem.AppendLine('# Full Windows trusted root store, exported for tools that ship their own CA bundle.')
    [void]$bundlePem.AppendLine("# Generated $(Get-Date -Format 'u') by work-setup.ps1. Re-run after any root CA rotation.")
    $seen = @{}
    foreach ($cert in $allRoots) {
        if ($seen.ContainsKey($cert.Thumbprint)) { continue }
        $seen[$cert.Thumbprint] = $true
        [void]$bundlePem.AppendLine((ConvertTo-Pem -Certificate $cert))
    }
    Write-TextFile -Path $WindowsBundle -Content $bundlePem.ToString()
    Write-Ok "wrote $WindowsBundle ($($seen.Count) certificates)"

    # Point each family of tools at the right bundle.
    #   Additive  -> corporate roots only
    #   Replacing -> the full Windows store
    $certEnv = [ordered]@{
        'NODE_EXTRA_CA_CERTS' = $CorporateRoots   # node, npm, pnpm, yarn, vite
        'REQUESTS_CA_BUNDLE'  = $WindowsBundle    # Azure CLI, python requests
        'SSL_CERT_FILE'       = $WindowsBundle    # OpenSSL-based tools
        'CURL_CA_BUNDLE'      = $WindowsBundle    # curl, Mason in Neovim
        'PIP_CERT'            = $WindowsBundle    # pip
    }

    foreach ($name in $certEnv.Keys) {
        $value = $certEnv[$name]
        [Environment]::SetEnvironmentVariable($name, $value, 'User')
        Set-Item -Path "Env:\$name" -Value $value
        Write-Ok "$name -> $(Split-Path -Leaf $value)"
    }

    # Git on Windows should use schannel so it reads the Windows store
    # directly and needs no bundle of its own.
    if (Test-Command git) {
        Invoke-Native -FilePath 'git' -ArgumentList @('config', '--global', 'http.sslBackend', 'schannel') | Out-Null
        # Deep node_modules paths on React projects routinely exceed 260 chars.
        Invoke-Native -FilePath 'git' -ArgumentList @('config', '--global', 'core.longpaths', 'true') | Out-Null
        Write-Ok 'git: http.sslBackend=schannel, core.longpaths=true'
    } else {
        Write-Warn 'git not found; skipped git TLS configuration.'
    }

    # Flag the dangerous workaround people apply when this goes wrong.
    if (Test-Command npm) {
        $strictSsl = ''
        try {
            $ErrorActionPreference = 'Continue'
            $strictSsl = (& npm config get strict-ssl 2>$null | Out-String).Trim()
        } catch {
            $strictSsl = ''
        } finally {
            $ErrorActionPreference = 'Stop'
        }

        if ($strictSsl -eq 'false') {
            Write-Warn 'npm has strict-ssl=false, which disables certificate verification.'
            Write-Detail 'Now that the CA is trusted, re-enable it: npm config set strict-ssl true'
        }
    }

    # Report an explicit proxy rather than guessing, since a wrong value
    # breaks more than it fixes.
    $ieProxy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction SilentlyContinue
    if ($ieProxy -and $ieProxy.ProxyEnable -eq 1 -and $ieProxy.ProxyServer) {
        Write-Warn "An explicit system proxy is configured: $($ieProxy.ProxyServer)"
        Write-Detail 'If tools still fail, set HTTP_PROXY and HTTPS_PROXY to it and add NO_PROXY for internal hosts.'
    }
}

# -- 3. Configuration ----------------------------------------------------------

$PowerShellProfileContent = @'
# Work machine PowerShell profile. Managed by dotfiles/windows/work-setup.ps1.

# Keep portable tool configuration on the same paths used on macOS and Linux.
$env:STARSHIP_CONFIG = Join-Path $HOME '.config\starship.toml'
$env:ATUIN_CONFIG_DIR = Join-Path $HOME '.config\atuin'

# Nerd Font glyphs and box drawing need a UTF-8 console.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

# Keep tooling telemetry off on a client machine.
$env:POWERSHELL_TELEMETRY_OPTOUT = 1
$env:DOTNET_CLI_TELEMETRY_OPTOUT = 1
$env:DOTNET_NOLOGO = 1
$env:AZURE_CORE_COLLECT_TELEMETRY = 0

# -- History and editing -------------------------------------------------------
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -BellStyle None

    # Never persist a command that starts with a space (same as zsh's
    # HIST_IGNORE_SPACE on macOS) or that looks like it carries a secret.
    Set-PSReadLineOption -AddToHistoryHandler {
        param($line)
        if ($line -match '^\s') { return $false }
        $sensitive = 'password', 'secret', 'token', 'apikey', 'api-key', 'connectionstring', '--key'
        foreach ($word in $sensitive) {
            if ($line -like "*$word*") { return $false }
        }
        return $true
    }

    try {
        # Inline grey suggestion from local history; no network, no service.
        Set-PSReadLineOption -PredictionSource History
        Set-PSReadLineOption -PredictionViewStyle InlineView
    } catch {
        # Older PSReadLine has no prediction; everything else still applies.
    }

    # Up/Down search history by what has been typed so far.
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
}

# -- Listing colours -----------------------------------------------------------
# PowerShell 7 paints directory names with a solid blue background. Use bold
# blue text instead, matching eza on macOS.
if ($PSStyle) {
    $PSStyle.FileInfo.Directory = "$([char]27)[1;34m"
}

# -- Aliases -------------------------------------------------------------------
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function which { param($name) (Get-Command $name -ErrorAction SilentlyContinue).Source }
function g { & git @args }

# Same aliases as macOS when the tools are installed, built-ins otherwise.
if (Get-Command eza -CommandType Application -ErrorAction SilentlyContinue) {
    Remove-Item Alias:ls -Force -ErrorAction SilentlyContinue
    function ls { eza --icons --group-directories-first @args }
    function ll { eza -la --icons --group-directories-first @args }
} else {
    function ll { Get-ChildItem -Force @args }
}

if (Get-Command bat -CommandType Application -ErrorAction SilentlyContinue) {
    Remove-Item Alias:cat -Force -ErrorAction SilentlyContinue
    function cat { bat @args }
}

# zoxide: smarter cd. Use 'z' instead of 'cd'.
if (Get-Command zoxide -CommandType Application -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

# -- Local LLM (Ollama + llm) --------------------------------------------------
# Everything runs on this machine. Conversation logging is turned off by
# work-setup.ps1, and commands starting with a space are not saved to history.
$script:LlmExe = (Get-Command llm -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1).Source

if ($script:LlmExe) {
    $script:LlmCliSubcommands = @(
        'aliases', 'collections', 'embed', 'install', 'keys', 'logs',
        'models', 'plugins', 'schemas', 'similar', 'templates', 'uninstall'
    )

    # 'llm cmd <request>': suggest a PowerShell command, show it, run it only
    # after confirmation. Mirrors the llm-cmd plugin used on macOS.
    function Invoke-LlmCommand {
        param([string]$Request)
        $system = 'Reply with one PowerShell 7 command for Windows that does what the user asks. ' +
                  'Output only the command, with no explanation and no code fences.'
        $suggestion = (& $script:LlmExe -s $system $Request | Out-String).Trim()
        # Keep only the fenced block if the model added one anyway.
        if ($suggestion -match '```[a-zA-Z]*\s*([\s\S]*?)```') { $suggestion = $Matches[1].Trim() }
        if (-not $suggestion) { Write-Host 'No suggestion returned.'; return }
        Write-Host ''
        Write-Host "  $suggestion" -ForegroundColor Yellow
        Write-Host ''
        if ((Read-Host 'Run it? [y/N]') -match '^[Yy]$') {
            & ([scriptblock]::Create($suggestion))
        }
    }

    function llm {
        if ($args.Count -gt 0 -and $args[0] -eq 'cmd') {
            Invoke-LlmCommand (($args | Select-Object -Skip 1) -join ' ')
        } elseif ($args.Count -gt 0 -and ($args[0] -like '-*' -or $script:LlmCliSubcommands -contains $args[0])) {
            if ($MyInvocation.ExpectingInput) {
                $input | & $script:LlmExe @args
            } else {
                & $script:LlmExe @args
            }
        } elseif ($MyInvocation.ExpectingInput) {
            $input | & $script:LlmExe -m terminal-llm @args
        } else {
            & $script:LlmExe -m terminal-llm @args
        }
    }

    # wtf: rerun the last command and ask the local model why it failed.
    # It reruns the command, so avoid it after anything destructive.
    function wtf {
        $last = Get-History -Count 1
        if (-not $last) { Write-Host 'No previous command.'; return }
        $command = $last.CommandLine
        $output = try { & ([scriptblock]::Create($command)) 2>&1 | Out-String } catch { $_ | Out-String }
        $tail = ($output -split "`r?`n" | Select-Object -Last 100) -join "`n"
        $tail | & $script:LlmExe "I ran this in PowerShell: $command`nExplain what went wrong and how to fix it."
    }
}

# -- Completions ---------------------------------------------------------------
# dotnet CLI tab completion, per Microsoft's documented snippet.
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# -- Prompt and history search -------------------------------------------------
# Searchable shell history on Ctrl-R and Up Arrow, stored locally. The guard
# keeps this profile working if Atuin could not be installed.
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    atuin init powershell | Out-String | Invoke-Expression
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
'@

$AtuinContent = @'
# Atuin shell history. Same settings as mac/config/atuin.toml.
dialect = "uk"
timezone = "local"

search_mode = "fuzzy"
search_mode_shell_up_key_binding = "prefix"
filter_mode = "global"
filter_mode_shell_up_key_binding = "directory"
workspaces = true

style = "compact"
inline_height = 30
show_preview = true

enter_accept = false
store_failed = true

# Privacy. secrets_filter drops anything shaped like a credential. The
# history_filter entries are regular expressions matched against the whole
# command line; the first is the leading-space convention from zsh's
# HIST_IGNORE_SPACE, so prefixing a command with a space keeps it out of
# history. Single quotes are TOML literal strings, so the backslash is literal.
secrets_filter = true
history_filter = [
  '^\s',
  '(?i)password',
  '(?i)secret',
  '(?i)token',
  '(?i)api[-_]?key',
]

# History never leaves this machine: no account, no server, no update ping.
# Do not run "atuin login".
auto_sync = false
update_check = false
'@

$StarshipContent = @'
"$schema" = "https://starship.rs/config-schema.json"

# Minimal Catppuccin prompt, matching the macOS setup.
# Left: where am I and what is the Git state.
# Right: how long that took, and which runtime this project uses.
add_newline = false
format = "$directory$git_branch$git_status$character"
right_format = "$cmd_duration$nodejs$dotnet$docker_context$azure"

[directory]
style = "bold #89b4fa"
format = "[$path]($style)"
truncation_length = 2
truncate_to_repo = true
read_only = " \U000F033E"

[git_branch]
symbol = "\uE0A0 "
style = "#cba6f7"
format = " [$symbol$branch]($style)"
truncation_length = 32
truncation_symbol = "\u2026"

[git_status]
style = "#f9e2af"
format = " [$all_status$ahead_behind]($style)"
conflicted = "="
ahead = "\u21E1${count}"
behind = "\u21E3${count}"
diverged = "\u21D5${ahead_count}/${behind_count}"
up_to_date = ""
untracked = "?"
stashed = "\\$"
modified = "!"
staged = "+"
renamed = "\u00BB"
deleted = "\u00D7"

# Only renders in a Node project.
[nodejs]
symbol = "\uE718 "
style = "#a6e3a1"
format = "[$symbol$version]($style) "

# Only renders next to a .csproj, .sln or global.json.
[dotnet]
symbol = "\uE77F "
style = "#cba6f7"
format = "[$symbol($version )($tfm )]($style)"
heuristic = true

# Only renders when the Docker context is not the default one, so a normal
# Docker Desktop setup stays silent.
[docker_context]
symbol = "\uE7B0 "
style = "#89dceb"
format = "[$symbol$context]($style) "
only_with_files = true

# Off by default to keep the prompt clean. Set disabled = false to show the
# active subscription, which is a cheap guard against deploying to the wrong
# one. Note it will then appear in every screen share.
[azure]
disabled = true
symbol = "az "
style = "#89b4fa"
format = "[$symbol($subscription)]($style) "

[cmd_duration]
min_time = 2_000
show_milliseconds = false
style = "dimmed #6c7086"
format = "[$duration]($style) "

[character]
success_symbol = " [\u276F](bold #a6e3a1)"
error_symbol = " [\u276F](bold #f38ba8)"
vimcmd_symbol = " [\u276E](bold #cba6f7)"
'@

if (-not $SkipConfig) {
    Write-Section 'Configuration'

    $fontFace = Resolve-TerminalFont
    if (-not $fontFace) {
        $fontFace = Resolve-FallbackFont
        Write-Warn "No Nerd Font is installed. Falling back to '$fontFace'."
        Write-Detail 'Prompt icons will render as boxes until a Nerd Font is installed.'
        Write-Detail 'Retry:  winget install --id DEVCOM.JetBrainsMonoNerdFont --source winget'
        Write-Detail 'Or download JetBrainsMono.zip from the Nerd Fonts releases page, extract it,'
        Write-Detail 'select the .ttf files and choose "Install for all users", then re-run this script.'
    } else {
        Write-Ok "Terminal font: $fontFace"
    }

    # A distinct GUID from the personal setup, so both profiles can coexist.
    $terminalFragment = @"
{
  "profiles": [
    {
      "name": "Work PowerShell",
      "guid": "{8f2b1d64-5c93-4a17-9b0e-2d7a6c48e315}",
      "commandline": "pwsh.exe -NoLogo",
      "startingDirectory": "%USERPROFILE%",
      "hidden": false,
      "colorScheme": "Minimal Catppuccin Mocha",
      "font": {
        "face": "$fontFace",
        "size": 11,
        "weight": "normal"
      },
      "opacity": 95,
      "useAcrylic": true,
      "padding": "12, 10, 12, 10",
      "cursorShape": "filledBox",
      "antialiasingMode": "grayscale",
      "scrollbarState": "hidden",
      "snapOnInput": true,
      "historySize": 20000
    }
  ],
  "schemes": [
    {
      "name": "Minimal Catppuccin Mocha",
      "background": "#1E1E2E",
      "foreground": "#CDD6F4",
      "cursorColor": "#F5E0DC",
      "selectionBackground": "#585B70",
      "black": "#45475A",
      "red": "#F38BA8",
      "green": "#A6E3A1",
      "yellow": "#F9E2AF",
      "blue": "#89B4FA",
      "purple": "#F5C2E7",
      "cyan": "#94E2D5",
      "white": "#BAC2DE",
      "brightBlack": "#585B70",
      "brightRed": "#F38BA8",
      "brightGreen": "#A6E3A1",
      "brightYellow": "#F9E2AF",
      "brightBlue": "#89B4FA",
      "brightPurple": "#F5C2E7",
      "brightCyan": "#94E2D5",
      "brightWhite": "#A6ADC8"
    }
  ]
}
"@

    # PowerShell 7 reads its profile from the user's Documents folder, which is
    # frequently redirected to OneDrive on a managed machine.
    $documents = [Environment]::GetFolderPath('MyDocuments')
    $profilePath = Join-Path $documents 'PowerShell\Microsoft.PowerShell_profile.ps1'
    $fragmentPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\eddie-work\work.json'

    Install-Config -Path $profilePath  -Content $PowerShellProfileContent
    Install-Config -Path (Join-Path $HOME '.config\starship.toml') -Content $StarshipContent
    Install-Config -Path (Join-Path $HOME '.config\atuin\config.toml') -Content $AtuinContent
    Install-Config -Path $fragmentPath -Content $terminalFragment

    # The PowerShell integration arrived well before any version WinGet carries,
    # but say so plainly rather than leaving a silent no-op in the profile.
    if (Test-Command atuin) {
        $atuinInit = (Invoke-Native -FilePath 'atuin' -ArgumentList @('init', 'powershell'))
        if ($atuinInit -eq 0) {
            Write-Ok "Atuin history search enabled ($((& atuin --version) -join ' '))."
        } else {
            Write-Warn 'This Atuin build does not support "atuin init powershell"; history search is off.'
        }
    } else {
        Write-Warn 'Atuin is not installed, so Ctrl-R falls back to PSReadLine search.'
    }

    if ($documents -like '*OneDrive*') {
        Write-Warn 'Your Documents folder is redirected to OneDrive.'
        Write-Detail "Profile written to $profilePath, which is where pwsh reads it from."
    }
}

# -- 4. Local LLM --------------------------------------------------------------

$script:LocalLlmReady = $false

function Invoke-NativeLive {
    # Like Invoke-Native, but lets progress output (model downloads) through.
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )
    $ErrorActionPreference = 'Continue'
    try {
        & $FilePath @ArgumentList | Out-Host
        return $LASTEXITCODE
    } catch {
        Write-Warn "$FilePath failed: $($_.Exception.Message)"
        return 1
    }
}

function Test-OllamaReady {
    return (Invoke-Native -FilePath 'ollama' -ArgumentList @('list')) -eq 0
}

function Start-OllamaServer {
    # The tray app normally runs the server. Start one if it is not up, and
    # give it a few seconds: a cold start has to load its runners first.
    if (Test-OllamaReady) { return $true }
    try {
        Start-Process -FilePath 'ollama' -ArgumentList 'serve' -WindowStyle Hidden
    } catch {
        Write-Detail "could not start ollama serve: $($_.Exception.Message)"
    }
    foreach ($attempt in 1..20) {
        if (Test-OllamaReady) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Restart-OllamaServer {
    # OLLAMA_* is read once at startup, so a server that is already running
    # keeps the old settings until it is restarted.
    Write-Detail 'restarting Ollama so the new settings take effect'
    foreach ($processName in @('ollama app', 'ollama')) {
        Get-Process -Name $processName -ErrorAction SilentlyContinue |
            Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    return (Start-OllamaServer)
}

function Get-NvidiaVramGb {
    # Dedicated VRAM on the largest NVIDIA GPU, or $null when there is none.
    # nvidia-smi ships with the driver and reports whole MiB.
    if (-not (Test-Command 'nvidia-smi')) { return $null }
    try {
        $ErrorActionPreference = 'Continue'
        $reported = & nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>$null
        $largest = @($reported | ForEach-Object { $_ -as [int] } | Where-Object { $_ }) |
            Sort-Object -Descending | Select-Object -First 1
        if (-not $largest) { return $null }
        return [math]::Round($largest / 1024)
    } catch {
        return $null
    }
}

if (-not $SkipLlm) {
    Write-Section 'Local LLM'

    # uv fetches Python and llm over TLS. Behind an inspecting proxy it must
    # read the Windows trust store instead of its own bundled roots. This
    # verifies certificates as normal, it just trusts the right ones.
    [Environment]::SetEnvironmentVariable('UV_NATIVE_TLS', '1', 'User')
    $env:UV_NATIVE_TLS = '1'

    # Ollama settings, persisted as user environment variables. On Windows
    # these survive a reboot, which is what launchctl does for the Mac setup.
    #
    # OLLAMA_HOST binds the server to loopback, so nothing on the corporate
    # network can reach it. Leave "Expose Ollama to the network" switched off
    # in the Ollama app as well, and never sign in to an Ollama account: this
    # setup is entirely local and uses no cloud models.
    $ollamaSettings = [ordered]@{
        'OLLAMA_HOST'              = '127.0.0.1:11434'  # loopback only
        'OLLAMA_FLASH_ATTENTION'   = '1'                # faster attention kernels
        'OLLAMA_KV_CACHE_TYPE'     = 'q8_0'             # smaller KV cache, more context per GB
        'OLLAMA_NUM_PARALLEL'      = '1'                # one request at a time
        'OLLAMA_MAX_LOADED_MODELS' = '1'                # never hold two models in memory
    }
    $ollamaSettingsChanged = $false
    foreach ($name in $ollamaSettings.Keys) {
        $value = $ollamaSettings[$name]
        if ([Environment]::GetEnvironmentVariable($name, 'User') -ne $value) {
            $ollamaSettingsChanged = $true
        }
        [Environment]::SetEnvironmentVariable($name, $value, 'User')
        Set-Item -Path "Env:\$name" -Value $value
    }
    Write-Ok 'Ollama pinned to 127.0.0.1:11434, one model loaded, q8_0 KV cache.'

    $llmReady = $true

    if (-not $SkipInstalls -and (Test-Command winget)) {
        # Both install per-user without administrator rights.
        if (-not (Install-WinGetPackage -Id 'Ollama.Ollama' -DisplayName 'Ollama' -Command 'ollama.exe')) {
            # Usually a blocked download rather than a blocked package, so try
            # the release archive on github.com before giving up.
            Write-Detail 'falling back to the Ollama release archive'
            Install-ArchiveToLocal -Url $OllamaReleaseUrl -Name 'ollama' -ExeName 'ollama.exe' -DisplayName 'Ollama' | Out-Null
        }
        Install-WinGetPackage -Id 'astral-sh.uv' -DisplayName 'uv' -Command 'uv.exe' | Out-Null
    }

    # uv installs tools into ~/.local/bin; make sure that is on PATH.
    $uvBin = Join-Path $HOME '.local\bin'
    if (Test-Command uv) {
        Invoke-Native -FilePath 'uv' -ArgumentList @('tool', 'update-shell') | Out-Null
        if ($env:Path -notlike "*$uvBin*") { $env:Path = "$uvBin;$env:Path" }
        Update-SessionPath
    }

    if (-not (Test-Command ollama) -or -not (Test-Command uv)) {
        Write-Warn 'Ollama or uv is missing, so the local LLM was not set up.'
        Write-Detail 'Install them (winget install Ollama.Ollama / astral-sh.uv), then re-run.'
        $llmReady = $false
    }

    if ($llmReady) {
        # The llm CLI with the Ollama plugin, as an isolated uv tool.
        if (-not (Test-Command llm)) {
            Write-Info 'Installing the llm CLI...'
            $code = Invoke-NativeLive -FilePath 'uv' -ArgumentList @('tool', 'install', 'llm', '--with', 'llm-ollama')
            Update-SessionPath
            if ($env:Path -notlike "*$uvBin*") { $env:Path = "$uvBin;$env:Path" }
            if ($code -ne 0 -or -not (Test-Command llm)) {
                Write-Warn 'Could not install the llm CLI.'
                $llmReady = $false
            } else {
                Write-Ok 'llm installed with the llm-ollama plugin.'
            }
        } else {
            Write-Ok 'llm already present.'
        }
    }

    if ($llmReady) {
        # Privacy: never store prompts or replies.
        Invoke-Native -FilePath 'llm' -ArgumentList @('logs', 'off') | Out-Null
        Write-Ok 'llm conversation logging turned off.'

        # A server that was already running predates the settings above.
        $serverUp = if ($ollamaSettingsChanged -and (Test-OllamaReady)) {
            Restart-OllamaServer
        } else {
            Start-OllamaServer
        }
        if (-not $serverUp) {
            Write-Warn 'The Ollama server did not start. Open Ollama from the Start menu, then re-run.'
            $llmReady = $false
        }
    }

    if ($llmReady) {
        # Report the hardware Ollama will actually use. A laptop GPU rarely has
        # room for a model this size, so most layers run on the CPU and the
        # split is worth seeing. Check it later with: ollama ps
        $ramGb  = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
        $vramGb = Get-NvidiaVramGb
        if ($vramGb) {
            Write-Detail "hardware: ${ramGb}GB RAM, ${vramGb}GB dedicated NVIDIA VRAM"
        } else {
            Write-Detail "hardware: ${ramGb}GB RAM, no NVIDIA GPU detected (CPU inference)"
        }

        # Pick a model that fits the machine's RAM, matching the macOS setup.
        # Override with -LlmModel if you want to force a specific Ollama tag.
        if ($LlmModel) {
            $baseModel = $LlmModel
        } elseif ($ramGb -ge 32) {
            $baseModel = 'gemma4:26b'  # about 16GB
        } elseif ($ramGb -ge 16) {
            $baseModel = 'gemma4:12b'  # about 8GB
        } else {
            $baseModel = 'gemma4:e4b'  # small model for 8GB machines
        }
        Write-Info "Using $baseModel."

        if (-not $LlmModel -and $baseModel -ne 'gemma4:26b') {
            Write-Detail "chose $baseModel because this machine reports ${ramGb}GB RAM"
        }
        Write-Detail 'first run downloads several GB, so allow time on a throttled link'

        # 16K context: Ollama's 4K default silently cuts off pasted code.
        $modelfile = Join-Path ([IO.Path]::GetTempPath()) 'terminal-llm.Modelfile'
        Write-TextFile -Path $modelfile -Content "FROM $baseModel`nPARAMETER num_ctx 16384`n"

        $steps = @(
            @{ File = 'ollama'; Args = @('pull', $baseModel); Live = $true },
            @{ File = 'ollama'; Args = @('create', 'terminal-llm', '-f', $modelfile); Live = $false },
            @{ File = 'llm';    Args = @('models', 'default', 'terminal-llm'); Live = $false },
            # Thinking off for quick answers; turn on per prompt with -o think true.
            @{ File = 'llm';    Args = @('models', 'options', 'set', 'terminal-llm', 'think', 'false'); Live = $false }
        )
        $failed = $false
        foreach ($step in $steps) {
            $code = if ($step.Live) { Invoke-NativeLive -FilePath $step.File -ArgumentList $step.Args }
                    else { Invoke-Native -FilePath $step.File -ArgumentList $step.Args }
            if ($code -ne 0) {
                Write-Warn "Failed: $($step.File) $($step.Args -join ' ')"
                if ($step.File -eq 'ollama' -and $step.Args[0] -eq 'pull') {
                    Write-Detail 'Ollama model blobs are redirected to *.r2.cloudflarestorage.com.'
                    Write-Detail 'If the pull reports EOF immediately, ask IT to allow that host category for Ollama downloads.'
                    Write-Detail 'A network that allows registry.ollama.ai but blocks Cloudflare R2 produces this exact failure.'
                }
                $failed = $true
                break
            }
        }
        Remove-Item -LiteralPath $modelfile -ErrorAction SilentlyContinue

        if (-not $failed) {
            $script:LocalLlmReady = $true
            Write-Ok "Local LLM ready: terminal-llm ($baseModel, 16K context, thinking off)."
        }
    }
}

# -- Summary -------------------------------------------------------------------

Write-Section 'Font check'
Write-Host '   If the next line shows boxes, the Nerd Font is not active yet.'
Write-Host '   Close every Windows Terminal window first: a per-user font is only'
Write-Host '   picked up by applications started after it was registered.'
# Built from code points rather than written literally, so this script stays
# pure ASCII and cannot be mangled by a shell that misreads its encoding.
$glyphs = @(0xE718, 0xE0B0, 0xE7B0, 0xE0A0, 0xE77F, 0xF033E) | ForEach-Object { [char]::ConvertFromUtf32($_) }
Write-Host ('           ' + ($glyphs -join '  ')) -ForegroundColor Magenta

Write-Section 'Done'
Write-Host 'Next:'
Write-Host '  1. Close and reopen Windows Terminal.'
Write-Host '  2. Pick "Work PowerShell" from the new-tab dropdown, then set it as'
Write-Host '     default under Settings > Startup > Default profile.'
Write-Host '  3. Open a NEW terminal so the environment variables are inherited.'
Write-Host '  4. Verify TLS: npm ping, az account show, git ls-remote <a repo>'
Write-Host '  5. Check everything at once: pwsh -File .\verify-work-setup.ps1'
Write-Host '     (no -NoProfile: several checks look at what the profile defines)'
if (-not $SkipLlm) {
    Write-Host ''
    Write-Host 'Local LLM:'
    if ($script:LocalLlmReady) {
        Write-Detail '  ask       llm "Say hi in five words"'
        Write-Detail '  suggest   llm cmd show the current date      (asks before running)'
        Write-Detail '  explain   wtf                                (reruns the last command)'
        Write-Detail '  split     ollama ps                          (how much is on the GPU)'
        Write-Detail '  private   runs locally, logging off, no account, loopback only'
    } else {
        Write-Detail '  not ready yet; re-run this script so Ollama can finish pulling and building terminal-llm'
        Write-Detail '  to force a smaller model, try: .\work-setup.ps1 -SkipInstalls -LlmModel gemma4:e4b'
    }
}
if (-not $SkipCerts) {
    Write-Host ''
    Write-Host 'Certificates:'
    Write-Detail "  bundles   $CertDirectory"
    Write-Detail "  refresh   re-run this script after any corporate CA rotation"
    Write-Detail "  undo      .\work-setup.ps1 -RemoveCertEnv"
}
if (Test-Path -LiteralPath $BackupDirectory) {
    Write-Host ''
    Write-Detail "Backups: $BackupDirectory"
}
Write-Host ''
