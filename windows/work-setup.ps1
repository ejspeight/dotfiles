#Requires -Version 5.1

<#
.SYNOPSIS
  Corporate-friendly Windows terminal setup: Windows Terminal, PowerShell 7,
  Starship and TLS trust plumbing for a TLS-inspecting proxy such as Zscaler.

.DESCRIPTION
  Written for a managed client machine where the toolchain (Node, Docker,
  Neovim, .NET) is already installed and the main friction is TLS inspection.

  It does three things, each independently skippable:

    1. Installs only terminal components: Windows Terminal, PowerShell 7,
       Starship and a Nerd Font. Never languages, runtimes or SDKs.
    2. Detects the corporate TLS-inspection root CA, exports PEM bundles and
       points the tools that carry their own CA store at them.
    3. Writes a PowerShell profile, a Starship prompt and a Windows Terminal
       fragment.

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
  Skip the PowerShell profile, Starship config and Windows Terminal fragment.

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

# ── Paths ─────────────────────────────────────────────────────────────────────

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

# ── Output helpers ────────────────────────────────────────────────────────────

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

# ── Undo path ─────────────────────────────────────────────────────────────────

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

# ── Preflight ─────────────────────────────────────────────────────────────────

Write-Host ''
Write-Host 'Windows Work Terminal Setup' -ForegroundColor White
Write-Host '---------------------------'

if ($PSVersionTable.PSVersion.Major -ge 6 -and -not $IsWindows) {
    throw 'This script must run on Windows.'
}

$IsAdmin = Test-Administrator
$Scope   = if ($IsAdmin) { 'machine' } else { 'user' }
Write-Detail "Running as $(if ($IsAdmin) { 'administrator' } else { 'standard user' }); WinGet scope: $Scope"

# ── 1. Terminal components ────────────────────────────────────────────────────

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

function Resolve-TerminalFont {
    # Preference order: the mac font, then the Nerd Font variants that ship
    # with Windows Terminal itself, which need no download at all.
    $preferences = @(
        @{ Face = 'JetBrainsMono Nerd Font'; Match = 'JetBrainsMono*Nerd Font*' },
        @{ Face = 'CaskaydiaCove Nerd Font'; Match = 'CaskaydiaCove*Nerd Font*' },
        @{ Face = 'Cascadia Mono NF';        Match = 'Cascadia Mono NF*' },
        @{ Face = 'Cascadia Code NF';        Match = 'Cascadia Code NF*' }
    )

    $installed = Get-InstalledFontNames
    foreach ($preference in $preferences) {
        foreach ($name in $installed) {
            if ($name -like $preference.Match) { return $preference.Face }
        }
    }
    return $null
}

if (-not $SkipInstalls) {
    Write-Section 'Terminal components'

    if (-not (Test-Command winget)) {
        Write-Warn 'WinGet is unavailable. Skipping installs and continuing with certificates and config.'
        Write-Detail 'Install "App Installer" from the Microsoft Store, or ask IT, then re-run.'
    } else {
        Install-WinGetPackage -Id 'Microsoft.WindowsTerminal' -DisplayName 'Windows Terminal' -Command 'wt.exe'  | Out-Null
        Install-WinGetPackage -Id 'Microsoft.PowerShell'      -DisplayName 'PowerShell 7'     -Command 'pwsh.exe' | Out-Null
        Install-WinGetPackage -Id 'Starship.Starship'         -DisplayName 'Starship'         -Command 'starship.exe' | Out-Null

        if (-not (Resolve-TerminalFont)) {
            Install-WinGetPackage -Id 'DEVCOM.JetBrainsMonoNerdFont' -DisplayName 'JetBrains Mono Nerd Font' | Out-Null
        } else {
            Write-Ok "Nerd Font already present."
        }
    }
    Update-SessionPath
}

# ── 2. Corporate TLS trust ────────────────────────────────────────────────────

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

# ── 3. Configuration ──────────────────────────────────────────────────────────

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

# ── History and editing ───────────────────────────────────────────────────────
if (Get-Module -ListAvailable -Name PSReadLine) {
    Import-Module PSReadLine
    Set-PSReadLineOption -EditMode Windows
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -BellStyle None

    # Never persist a command that looks like it carries a secret.
    Set-PSReadLineOption -AddToHistoryHandler {
        param($line)
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

# ── Aliases ───────────────────────────────────────────────────────────────────
function .. { Set-Location .. }
function ... { Set-Location ..\.. }
function ll { Get-ChildItem -Force @args }
function which { param($name) (Get-Command $name -ErrorAction SilentlyContinue).Source }
function g { & git @args }

# ── Completions ───────────────────────────────────────────────────────────────
# dotnet CLI tab completion, per Microsoft's documented snippet.
Register-ArgumentCompleter -Native -CommandName dotnet -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    dotnet complete --position $cursorPosition "$commandAst" | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

# ── Prompt and history search ─────────────────────────────────────────────────
# Atuin is optional. If it is ever installed, this picks it up automatically.
if (Get-Command atuin -ErrorAction SilentlyContinue) {
    atuin init powershell | Out-String | Invoke-Expression
}

if (Get-Command starship -ErrorAction SilentlyContinue) {
    Invoke-Expression (&starship init powershell)
}
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
read_only = " 󰌾"

[git_branch]
symbol = " "
style = "#cba6f7"
format = " [$symbol$branch]($style)"
truncation_length = 32
truncation_symbol = "…"

[git_status]
style = "#f9e2af"
format = " [$all_status$ahead_behind]($style)"
conflicted = "="
ahead = "⇡${count}"
behind = "⇣${count}"
diverged = "⇕${ahead_count}/${behind_count}"
up_to_date = ""
untracked = "?"
stashed = "\\$"
modified = "!"
staged = "+"
renamed = "»"
deleted = "×"

# Only renders in a Node project.
[nodejs]
symbol = " "
style = "#a6e3a1"
format = "[$symbol$version]($style) "

# Only renders next to a .csproj, .sln or global.json.
[dotnet]
symbol = " "
style = "#cba6f7"
format = "[$symbol($version )($tfm )]($style)"
heuristic = true

# Only renders when the Docker context is not the default one, so a normal
# Docker Desktop setup stays silent.
[docker_context]
symbol = " "
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
success_symbol = " [❯](bold #a6e3a1)"
error_symbol = " [❯](bold #f38ba8)"
vimcmd_symbol = " [❮](bold #cba6f7)"
'@

if (-not $SkipConfig) {
    Write-Section 'Configuration'

    $fontFace = Resolve-TerminalFont
    if (-not $fontFace) {
        # Ships with Windows Terminal 1.19+, so this needs no download.
        $fontFace = 'Cascadia Mono NF'
        Write-Warn "No Nerd Font detected. Using '$fontFace', bundled with Windows Terminal."
        Write-Detail 'For JetBrains Mono, download JetBrainsMono.zip from the Nerd Fonts releases'
        Write-Detail 'page, then right-click the .ttf files and choose "Install for all users".'
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
    Install-Config -Path $fragmentPath -Content $terminalFragment

    if ($documents -like '*OneDrive*') {
        Write-Warn 'Your Documents folder is redirected to OneDrive.'
        Write-Detail "Profile written to $profilePath, which is where pwsh reads it from."
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────

Write-Section 'Font check'
Write-Host '   If the next line shows boxes, the Nerd Font is not active yet:'
Write-Host "           󰌾  " -ForegroundColor Magenta

Write-Section 'Done'
Write-Host 'Next:'
Write-Host '  1. Close and reopen Windows Terminal.'
Write-Host '  2. Pick "Work PowerShell" from the new-tab dropdown, then set it as'
Write-Host '     default under Settings > Startup > Default profile.'
Write-Host '  3. Open a NEW terminal so the certificate variables are inherited.'
Write-Host '  4. Verify TLS: npm ping, az account show, git ls-remote <a repo>'
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
