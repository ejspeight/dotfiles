#Requires -Version 5.1

<#
.SYNOPSIS
  Checks that work-setup.ps1 did what it claims, and prints a report that can
  be pasted straight into an issue or a message.

.DESCRIPTION
  Read-only. Nothing is installed, changed or downloaded unless -Benchmark is
  given, which pulls models.

  Run it from a normal shell, NOT with -NoProfile: several checks look at the
  functions the profile defines.

.PARAMETER Benchmark
  Also compare model speeds. This downloads any model not already present,
  which is several GB, and takes a few minutes.

.PARAMETER BenchmarkModel
  Models to compare. Defaults to the mixture-of-experts model the setup picks
  and the dense model of roughly half the size.

.EXAMPLE
  pwsh -File .\verify-work-setup.ps1

.EXAMPLE
  pwsh -File .\verify-work-setup.ps1 -Benchmark
#>

[CmdletBinding()]
param(
    [switch]$Benchmark,
    [string[]]$BenchmarkModel = @('gemma4:26b', 'gemma4:12b')
)

$ProgressPreference = 'SilentlyContinue'

$script:Pass = 0
$script:Fail = 0
$script:Warn = 0

function Write-Section { param([string]$Message) Write-Host ''; Write-Host "== $Message" -ForegroundColor White }
function Write-Detail  { param([string]$Message) Write-Host "     $Message" -ForegroundColor DarkGray }
function Write-Pass    { param([string]$Message) $script:Pass++; Write-Host "  OK $Message" -ForegroundColor Green }
function Write-Fail    { param([string]$Message) $script:Fail++; Write-Host "FAIL $Message" -ForegroundColor Red }
function Write-Note { param([string]$Message) $script:Warn++; Write-Host "  ! $Message" -ForegroundColor Yellow }

function Test-Command { param([string]$Name) return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue) }

function Get-NonAsciiLines {
    # Returns the first few lines holding a byte above 127, with the line
    # number, so mojibake is easy to spot.
    param([string]$Path, [int]$Limit = 5)

    $found = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $found }
    $number = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $number++
        if ($line -match '[^\x00-\x7F]') {
            $found += "line ${number}: $line"
            if ($found.Count -ge $Limit) { break }
        }
    }
    return $found
}

Write-Host ''
Write-Host 'Windows Work Setup Verification' -ForegroundColor White
Write-Host '-------------------------------'
Write-Detail "host      $($PSVersionTable.PSEdition) $($PSVersionTable.PSVersion)"
Write-Detail "profile   $PROFILE"
Write-Detail "loaded    $(if (Get-Command starship -ErrorAction SilentlyContinue) { 'yes' } else { 'no - re-run without -NoProfile' })"

# -- 1. Script parses ----------------------------------------------------------

Write-Section '1. Script and profile parse'

$setupPath = Join-Path $PSScriptRoot 'work-setup.ps1'
if (-not (Test-Path -LiteralPath $setupPath)) {
    Write-Note "work-setup.ps1 is not next to this script, skipped the parse check."
} else {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$null, [ref]$parseErrors) | Out-Null
    if ($parseErrors) {
        Write-Fail "work-setup.ps1 has $($parseErrors.Count) parse error(s)"
        $parseErrors | Select-Object -First 5 | ForEach-Object {
            Write-Detail "line $($_.Extent.StartLineNumber): $($_.Message)"
        }
    } else {
        Write-Pass 'work-setup.ps1 parses with no errors'
    }

    # The embedded profile only fails at shell start otherwise, which is a
    # miserable place to find a typo.
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$null, [ref]$null)
    $node = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $n.Left.Extent.Text -eq '$PowerShellProfileContent'
    }, $true) | Select-Object -First 1

    if (-not $node) {
        Write-Note 'could not find the embedded profile to parse'
    } else {
        $body = $node.Right.Extent.Text -replace "^@'\r?\n", '' -replace "\r?\n'@$", ''
        $embeddedErrors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$null, [ref]$embeddedErrors) | Out-Null
        if ($embeddedErrors) {
            Write-Fail "the embedded profile has $($embeddedErrors.Count) parse error(s)"
        } else {
            Write-Pass 'embedded PowerShell profile parses with no errors'
        }
    }

    # -- 2. Encoding -----------------------------------------------------------

    Write-Section '2. Encoding'

    $bytes = [IO.File]::ReadAllBytes($setupPath)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if ($hasBom) { Write-Pass 'work-setup.ps1 has a UTF-8 BOM' }
    else { Write-Fail 'work-setup.ps1 has no UTF-8 BOM; PowerShell 5.1 will read it as ANSI' }

    $high = @($bytes | Where-Object { $_ -gt 127 }).Count
    $expected = if ($hasBom) { 3 } else { 0 }
    if ($high -le $expected) { Write-Pass 'work-setup.ps1 body is pure ASCII' }
    else { Write-Fail "work-setup.ps1 has $($high - $expected) non-ASCII bytes outside the BOM" }
}

foreach ($target in @($PROFILE, (Join-Path $HOME '.config\starship.toml'), (Join-Path $HOME '.config\atuin\config.toml'))) {
    $name = Split-Path -Leaf $target
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Note "$name does not exist"
        continue
    }
    $bad = Get-NonAsciiLines -Path $target
    if ($bad.Count -eq 0) {
        Write-Pass "$name is clean (no stray non-ASCII characters)"
    } else {
        Write-Fail "$name contains non-ASCII characters, which usually means mojibake"
        $bad | ForEach-Object { Write-Detail $_ }
    }
}

# -- 3. Fonts ------------------------------------------------------------------

Write-Section '3. Fonts and glyphs'

$hives = [ordered]@{
    'machine (HKLM)' = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
    'user (HKCU)'    = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
}
$nerdTotal = 0
foreach ($label in $hives.Keys) {
    $names = @()
    $item = Get-ItemProperty -Path $hives[$label] -ErrorAction SilentlyContinue
    if ($item) {
        $names = @($item.PSObject.Properties |
            Where-Object { $_.Name -notlike 'PS*' -and ($_.Name -like '*Nerd Font*' -or $_.Name -like '*JetBrains*') } |
            ForEach-Object { $_.Name })
    }
    $nerdTotal += $names.Count
    if ($names.Count -gt 0) {
        Write-Detail "$label : $($names.Count) entries"
        $names | Select-Object -First 6 | ForEach-Object { Write-Detail "    $_" }
    } else {
        Write-Detail "$label : none"
    }
}
if ($nerdTotal -gt 0) { Write-Pass "$nerdTotal Nerd Font registry entries found" }
else { Write-Fail 'no Nerd Font is registered in either hive; prompt icons will be boxes' }

$fragmentPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\eddie-work\work.json'
if (Test-Path -LiteralPath $fragmentPath) {
    try {
        $fragment = Get-Content -LiteralPath $fragmentPath -Raw | ConvertFrom-Json
        $face = $fragment.profiles[0].font.face
        Write-Detail "fragment profile : $($fragment.profiles[0].name)"
        Write-Detail "fragment font    : $face"
        if ($face -like '*Nerd Font*' -or $face -like '*NF*') {
            Write-Pass "the Work PowerShell profile asks for a Nerd Font ($face)"
        } else {
            Write-Fail "the profile fell back to '$face', which has no prompt glyphs"
        }
    } catch {
        Write-Note "could not read the terminal fragment: $($_.Exception.Message)"
    }
} else {
    Write-Fail "no Windows Terminal fragment at $fragmentPath"
}

Write-Host ''
Write-Host '     These should be a node, an arrow, a whale, a branch, a bracket and a lock:'
$glyphs = @(0xE718, 0xE0B0, 0xE7B0, 0xE0A0, 0xE77F, 0xF033E) | ForEach-Object { [char]::ConvertFromUtf32($_) }
Write-Host ('       ' + ($glyphs -join '  ')) -ForegroundColor Magenta
Write-Host ('     Prompt character: ' + [char]::ConvertFromUtf32(0x276F) + '   (a chevron, not two odd letters)') -ForegroundColor Magenta

# -- 4. Listing colours --------------------------------------------------------

Write-Section '4. Directory colours'

if (-not $PSStyle) {
    Write-Note '$PSStyle does not exist on this PowerShell; nothing to check'
} else {
    $directoryStyle = $PSStyle.FileInfo.Directory
    $readable = $directoryStyle -replace ([char]27), 'ESC'
    Write-Detail "PSStyle.FileInfo.Directory = $readable"
    if ($directoryStyle -match '4[0-7]m|10[0-7]m') {
        Write-Fail 'directories still have a background colour set'
    } elseif ($directoryStyle -match '1;34') {
        Write-Pass 'directories are bold blue text, with no background'
    } else {
        Write-Note 'directory style is set to something other than bold blue'
    }
    Write-Host ''
    Get-ChildItem -Path $HOME -Directory -ErrorAction SilentlyContinue | Select-Object -First 3 | Out-Host
}

# -- 5. Shell tools ------------------------------------------------------------

Write-Section '5. Shell tools'

foreach ($tool in @('pwsh', 'starship', 'atuin', 'git', 'node', 'ollama', 'uv', 'llm')) {
    $command = Get-Command $tool -ErrorAction SilentlyContinue
    if ($command) {
        $version = try { (& $tool --version 2>&1 | Select-Object -First 1) -replace '\s+', ' ' } catch { 'unknown' }
        Write-Pass "$tool : $version"
    } else {
        Write-Fail "$tool is not on PATH"
    }
}

if (Test-Command atuin) {
    $init = try { (& atuin init powershell 2>&1 | Out-String) } catch { '' }
    if ($init.Length -gt 100) { Write-Pass 'atuin init powershell produces a module' }
    else { Write-Fail 'atuin init powershell returned nothing usable' }
}

# -- 6. History privacy --------------------------------------------------------

Write-Section '6. History privacy'

$handler = (Get-PSReadLineOption).AddToHistoryHandler
if (-not $handler) {
    Write-Fail 'no AddToHistoryHandler is installed; nothing is being filtered'
} else {
    $cases = @(
        @{ Line = ' echo secret-free but space-prefixed'; Expect = $false; What = 'leading space' },
        @{ Line = 'echo hello';                           Expect = $true;  What = 'ordinary command' },
        @{ Line = 'setx MY_TOKEN abc123';                 Expect = $false; What = 'contains token' },
        @{ Line = '$env:PASSWORD = "hunter2"';            Expect = $false; What = 'contains password' },
        @{ Line = 'git status';                           Expect = $true;  What = 'ordinary git' }
    )
    $allGood = $true
    foreach ($case in $cases) {
        $result = [bool](& $handler $case.Line)
        $correct = ($result -eq $case.Expect)
        if (-not $correct) { $allGood = $false }
        $verdict = if ($correct) { 'OK   ' } else { 'WRONG' }
        $action  = if ($result) { 'stored  ' } else { 'filtered' }
        Write-Detail "$verdict $action  $($case.What)"
    }
    if ($allGood) { Write-Pass 'the history handler filters spaces and secrets correctly' }
    else { Write-Fail 'the history handler did not behave as expected' }
}

$historyPath = (Get-PSReadLineOption).HistorySavePath
if (Test-Path -LiteralPath $historyPath) {
    $spaced = @(Get-Content -LiteralPath $historyPath | Where-Object { $_ -match '^\s' -and $_.Trim() })
    if ($spaced.Count -eq 0) { Write-Pass 'no space-prefixed command has ever been saved to the history file' }
    else { Write-Fail "$($spaced.Count) space-prefixed line(s) are in $historyPath" }
} else {
    Write-Note "no history file at $historyPath yet"
}

Write-Host ''
Write-Detail 'The handler only runs on lines typed interactively, so finish the check by hand:'
Write-Detail '  1. type:   echo dotfiles-probe      (with ONE leading space)'
Write-Detail '  2. run:    Select-String dotfiles-probe (Get-PSReadLineOption).HistorySavePath'
Write-Detail '  3. run:    atuin search dotfiles-probe'
Write-Detail '  Both should find nothing.'

# -- 7. Local LLM --------------------------------------------------------------

Write-Section '7. Local LLM'

$expected = [ordered]@{
    'OLLAMA_HOST'              = '127.0.0.1:11434'
    'OLLAMA_FLASH_ATTENTION'   = '1'
    'OLLAMA_KV_CACHE_TYPE'     = 'q8_0'
    'OLLAMA_NUM_PARALLEL'      = '1'
    'OLLAMA_MAX_LOADED_MODELS' = '1'
}
foreach ($name in $expected.Keys) {
    $actual = [Environment]::GetEnvironmentVariable($name, 'User')
    if ($actual -eq $expected[$name]) { Write-Pass "$name = $actual (persisted for this user)" }
    else { Write-Fail "$name is '$actual', expected '$($expected[$name])'" }
}

if ([Environment]::GetEnvironmentVariable('UV_NATIVE_TLS', 'User') -eq '1') {
    Write-Pass 'UV_NATIVE_TLS = 1 (uv trusts the corporate root through the Windows store)'
} else {
    Write-Note 'UV_NATIVE_TLS is not set for this user'
}

if (Test-Command 'nvidia-smi') {
    Write-Host ''
    & nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv 2>&1 | Out-Host
} else {
    Write-Detail 'no nvidia-smi, so Ollama is running on the CPU'
}

if (Test-Command ollama) {
    Write-Host ''
    Write-Detail 'ollama ps (the CPU/GPU column is the split for the loaded model):'
    & ollama ps 2>&1 | Out-Host

    $models = (& ollama list 2>&1 | Out-String)
    if ($models -match 'terminal-llm') { Write-Pass 'the terminal-llm model exists' }
    else { Write-Fail 'terminal-llm was not built' }
}

if (Test-Command llm) {
    $default = try { (& llm models default 2>&1 | Out-String).Trim() } catch { '' }
    if ($default -match 'terminal-llm') { Write-Pass "llm default model is $default" }
    else { Write-Note "llm default model is '$default'" }

    Write-Host ''
    Write-Detail 'llm "Say hi in five words" ->'
    $answer = try { (& llm 'Say hi in five words' 2>&1 | Out-String).Trim() } catch { "ERROR: $($_.Exception.Message)" }
    Write-Host "       $answer" -ForegroundColor Cyan
    if ($answer -match '(?i)<think>|^Thinking') { Write-Fail 'the answer contains thinking output' }
    elseif ($answer) { Write-Pass 'the model answered' }
    else { Write-Fail 'the model returned nothing' }

    Write-Detail 'pipe test: "the cat sat on the mat" | llm "summarise in two words" ->'
    $piped = try { ('the cat sat on the mat' | llm 'summarise in two words' 2>&1 | Out-String).Trim() } catch { "ERROR: $($_.Exception.Message)" }
    Write-Host "       $piped" -ForegroundColor Cyan
    if ($piped -and $piped -notmatch '^ERROR') { Write-Pass 'the llm wrapper handles piped input' }
    else { Write-Fail 'piping into llm failed' }
}

foreach ($name in @('llm', 'wtf')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    if ($command -and $command.CommandType -eq 'Function') { Write-Pass "the $name profile function is loaded" }
    elseif ($command) { Write-Note "$name resolves to a $($command.CommandType), not the profile function" }
    else { Write-Fail "the $name function is missing (is the profile loaded?)" }
}

Write-Host ''
Write-Detail 'Finish the LLM check by hand, because it waits for input:'
Write-Detail '  run:  llm cmd show the current date'
Write-Detail '  It should print one command and wait at "Run it? [y/N]". Press n.'

# -- 8. Benchmark --------------------------------------------------------------

if ($Benchmark) {
    Write-Section '8. Model benchmark'

    $prompt = 'Write a PowerShell one-liner to list the 5 largest files in this folder'
    $results = @()

    foreach ($model in $BenchmarkModel) {
        Write-Host ''
        Write-Detail "pulling $model (skipped if already present)..."
        & ollama pull $model 2>&1 | Out-Null

        Write-Detail "running $model ..."
        $output = (& ollama run $model --verbose $prompt 2>&1 | Out-String)

        $evalRate = if ($output -match 'eval rate:\s+([\d.]+)\s+tokens/s') { [double]$Matches[1] } else { $null }
        $loadTime = if ($output -match 'load duration:\s+(\S+)') { $Matches[1] } else { 'n/a' }
        $split = ((& ollama ps 2>&1 | Out-String) -split "`r?`n" | Where-Object { $_ -match [regex]::Escape($model) }) -join ' '

        $results += [pscustomobject]@{
            Model    = $model
            TokensPerSecond = $evalRate
            LoadTime = $loadTime
            Split    = ($split -replace '\s{2,}', ' ')
        }
        Write-Detail "  eval rate: $(if ($evalRate) { "$evalRate tok/s" } else { 'not reported' })"
    }

    Write-Host ''
    $results | Format-Table -AutoSize | Out-Host

    $ranked = @($results | Where-Object { $_.TokensPerSecond } | Sort-Object TokensPerSecond -Descending)
    if ($ranked.Count -ge 2) {
        $best = $ranked[0]
        Write-Host ''
        Write-Pass "fastest: $($best.Model) at $($best.TokensPerSecond) tokens/s"
        if ($best.TokensPerSecond -lt 15) {
            Write-Note "that is below the 15 tokens/s target; consider a smaller model"
        }
        Write-Host ''
        Write-Detail 'Nothing was removed. To reclaim the space used by the slower models:'
        foreach ($loser in $ranked | Select-Object -Skip 1) {
            Write-Detail "  ollama rm $($loser.Model)"
        }
    }
} else {
    Write-Section '8. Model benchmark'
    Write-Detail 'Skipped. Re-run with -Benchmark to compare model speeds (downloads several GB).'
}

# -- Summary -------------------------------------------------------------------

Write-Section 'Summary'
Write-Host "  passed   $script:Pass" -ForegroundColor Green
Write-Host "  warnings $script:Warn" -ForegroundColor Yellow
Write-Host "  failed   $script:Fail" -ForegroundColor $(if ($script:Fail) { 'Red' } else { 'Green' })
Write-Host ''
if ($script:Fail -eq 0) {
    Write-Host 'Everything checked out. Paste this report back if anything looks wrong.' -ForegroundColor Green
} else {
    Write-Host 'Some checks failed. Re-run work-setup.ps1, open a NEW terminal, then run this again.' -ForegroundColor Yellow
}
Write-Host ''
