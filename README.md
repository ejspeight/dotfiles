# dotfiles

Personal machine setup scripts for getting a new machine up and running.

## Mac

Sets up a full dev environment including Ghostty, Codex, a minimal Catppuccin Starship prompt, searchable shell history, Neovim (LazyVim), Node, .NET, Rust, Go, and more.

```bash
cd mac
chmod +x setup.sh && ./setup.sh
```

### What gets installed

- **Homebrew:** package manager and all formulae
- **Neovim:** with [LazyVim](https://www.lazyvim.org) (plugins auto-install on first launch)
- **Terminal:** Ghostty with Catppuccin Mocha, JetBrains Mono Nerd Font, transparency and blur
- **Prompt:** minimal Starship layout with project, Git status, Node version and command duration
- **Shell:** Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, Atuin history and command-only typo correction
- **Languages:** Node (via nvm), Go, Rust (via rustup), Python, .NET SDK
- **Shell tools:** fzf, ripgrep, fd, bat, eza, zoxide, jq, lazygit, gh
- **AI:** Codex CLI application; its configuration and credentials remain local
- **Local LLM:** Ollama and the `llm` CLI, with a model chosen to fit the Mac's memory (see [Local LLM](#local-llm))
- **Apps:** Ghostty, Codex, Raycast, Rectangle, DBeaver, 1Password

### Terminal configuration

The editable source files live under [`mac/config`](mac/config):

| File | Installed to | Purpose |
|---|---|---|
| `zshrc` | `~/.zshrc` | Shell plugins, aliases, Atuin and Starship startup, `wtf` local LLM helper |
| `zprofile` | `~/.zprofile` | Homebrew environment for login shells |
| `starship.toml` | `~/.config/starship.toml` | Minimal prompt layout and Catppuccin colours |
| `atuin.toml` | `~/.config/atuin/config.toml` | History search and key behaviour |
| `ollama/Modelfile` | Built into the `terminal-llm` Ollama model | Chosen base model with a 16K context window |
| `ghostty/config.ghostty` | `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` | Font, theme, transparency and window behaviour |

Existing config files are copied to `~/.config-backups/dotfiles-<timestamp>/`
before replacement. The setup does not read, copy or modify Codex configuration
or credentials, and this repository does not track them.

### After running

1. Quit and reopen Ghostty, then run `exec zsh -l`
2. Run `codex login` and sign in with ChatGPT
3. Open `nvim`; LazyVim plugins install automatically
4. Enable the SSH agent in 1Password settings
5. Run `aws configure` to set up AWS credentials
6. Test the local LLM: `llm "Say hi in five words"`

### Local LLM

A private terminal assistant that runs entirely on the Mac. Prompts are never
sent to a cloud service.

`setup.sh` installs [Ollama](https://ollama.com) and the
[`llm`](https://llm.datasette.io) CLI, then picks a model based on the Mac's
memory:

| RAM | Model | Download |
|---|---|---|
| 8GB | `gemma4:e4b` | ~3GB |
| 16GB to 24GB | `gemma4:12b` | ~8GB |
| 32GB or more | `gemma4:26b` | ~16GB |

The chosen model is saved as `terminal-llm` with a 16K context window, set as
the `llm` default, and has thinking turned off for faster answers. To use a
different model, pass any [Ollama tag](https://ollama.com/library):

```bash
LOCAL_LLM_MODEL=qwen3.6:35b-a3b ./setup.sh
```

**Usage**

```bash
llm "explain what a git rebase does"             # quick question
llm chat                                         # back-and-forth chat
llm cmd find all files over 1GB here             # suggest a command, review, then run
git diff | llm "write a commit message"          # pipe output in
wtf                                              # rerun the last command and explain the failure
llm -o think true "why does this leak memory?"   # let the model think first
```

- Start a command with a space to keep it out of shell history.
- `wtf` reruns the last command, so do not use it after anything destructive.
- Conversation logging is turned off (`llm logs off`).

**Checking performance**

Run `ollama ps` while the model is loaded. `100% GPU` is what you want. A
CPU/GPU split means the model does not fit in memory, so close memory-heavy
apps or rerun the setup with a smaller `LOCAL_LLM_MODEL`.

## Linux

Minimal base setup for Ubuntu/Debian. Installs core tools via apt, then builds up the same shell environment as Mac.

```bash
cd linux
chmod +x setup.sh && ./setup.sh
```

### What gets installed

- **apt packages:** git, neovim, zsh, ripgrep, fd, fzf, bat, htop, jq, Go, and more
- **lazygit:** latest binary from GitHub releases
- **gh:** GitHub CLI via official apt repo
- **eza:** better `ls` via eza apt repo
- **zoxide:** smarter `cd`
- **Neovim:** with [LazyVim](https://www.lazyvim.org) (plugins auto-install on first launch)
- **Oh My Zsh:** with zsh-autosuggestions, zsh-syntax-highlighting, eastwood theme
- **Languages:** Node (via nvm), Rust (via rustup), Go
- **Shell tools:** fzf, ripgrep, fd, bat, eza, zoxide, jq, lazygit, gh

### After running

1. Restart your terminal (or `exec zsh`)
2. Open `nvim`; LazyVim plugins install automatically
3. Run `nvm install 23` if Node wasn't set up during the script

## Windows (work / managed machine)

For a corporate machine where the toolchain is already installed and the real
friction is TLS inspection and the lack of administrator rights. It touches the
terminal only, never languages, runtimes or SDKs.

`work-setup.ps1` is self-contained: it embeds its own PowerShell profile,
Starship config, Atuin config and Windows Terminal fragment, so it can be copied
to the client machine on its own without cloning this repository.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\work-setup.ps1
```

Then open a **new** terminal and check the result. Run this one without
`-NoProfile`, because several checks look at what the profile defines:

```powershell
pwsh -File .\verify-work-setup.ps1
```

### What it does

1. **Installs terminal components only:** Windows Terminal, PowerShell 7,
   Starship, Atuin and a Nerd Font, through WinGet's `winget` source (the
   Microsoft Store source is commonly blocked by policy). Every install is
   per-user and needs no administrator rights. A missing WinGet is a warning,
   not a failure; the rest still runs.
2. **Fixes TLS inspection:** detects the corporate root CA both by subject
   (Zscaler, Netskope, Palo Alto and other appliances) and by TLS-probing the
   hosts the toolchain actually uses, then exports PEM bundles and points every
   tool that ships its own CA store at them.
3. **Writes config:** a PowerShell profile, the same Catppuccin Starship prompt
   as macOS, an Atuin config, and a Windows Terminal profile fragment.
4. **Sets up a private local LLM:** Ollama, the `llm` CLI and a model built for
   terminal use. Nothing leaves the machine and no account is required.

### The stack

| Layer | Tool |
|---|---|
| Terminal | Windows Terminal |
| Shell | PowerShell 7 with PSReadLine |
| Prompt | Starship |
| History | Atuin |
| Local LLM | Ollama with the `llm` CLI |

Git and Node are configured but never installed: a managed machine already has
them, and this script does not touch runtimes. `eza`, `bat` and `zoxide` are not
installed either, but if you add them yourself the profile aliases `ls`, `ll`
and `cat` to match macOS and quietly stays on the built-ins otherwise.

### Where packages come from

Everything is per-user. When WinGet cannot supply a package the script falls
back to the vendor's own release archive, unpacked into `~/.local/bin`, which is
added to the user `PATH`.

| Package | WinGet id | Fallback |
|---|---|---|
| Windows Terminal | `Microsoft.WindowsTerminal` | — |
| PowerShell 7 | `Microsoft.PowerShell` | — |
| Starship | `Starship.Starship` | — |
| Atuin | `Atuinsh.Atuin` | GitHub release zip |
| Nerd Font | `DEVCOM.JetBrainsMonoNerdFont` | per-user font install |
| Ollama | `Ollama.Ollama` | — |
| uv | `astral-sh.uv` | — |
| `llm` | — | `uv tool install llm --with llm-ollama` |

### Fonts without administrator rights

WinGet's Nerd Font package installs machine-wide, so a managed device usually
refuses it and the prompt renders as empty boxes. When that happens the script
installs the font for the current user instead: it downloads the JetBrainsMono
archive from the Nerd Fonts releases, extracts the four faces it needs into
`%LOCALAPPDATA%\Microsoft\Windows\Fonts`, and registers them under
`HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts`. No elevation
involved. The real face name is read out of the font file so the Windows
Terminal fragment asks for exactly what was registered.

Both registry hives are listed on every run, so you can see what is actually
installed rather than guessing. Close every Windows Terminal window afterwards:
a per-user font only reaches applications started after it was registered.

### History

Atuin provides the same searchable history as macOS, entirely locally. The
script never runs `atuin login`, and the config sets `auto_sync = false` and
`update_check = false`, so nothing is sent anywhere.

Two independent filters keep secrets out of history, because PSReadLine and
Atuin record commands separately:

- **PSReadLine** drops any line that starts with a space, or that contains
  `password`, `secret`, `token`, `apikey`, `api-key`, `connectionstring` or
  `--key`.
- **Atuin** sets `secrets_filter = true` plus a `history_filter` with the same
  rules as regular expressions.

Prefixing a command with a single space therefore keeps it out of both, which is
the same convention as `HIST_IGNORE_SPACE` in the macOS zsh setup.

### Local LLM

Ollama runs the model, `llm` is the command-line front end, and `uv` installs
`llm` in its own isolated environment. `UV_NATIVE_TLS=1` makes uv read the
Windows trust store, so it works behind an inspecting proxy without any
certificate check being weakened.

The script builds a model named `terminal-llm` with a 16K context window, makes
it the `llm` default, turns thinking off for quick answers and runs `llm logs
off` so prompts and replies are never written to disk.

```powershell
llm "Say hi in five words"           # one-shot question
llm chat                             # conversation
llm cmd show the current date        # suggests a command, asks before running it
wtf                                  # reruns the last command, explains the failure
Get-Content error.log | llm "what broke?"
llm -o think true "harder question"  # thinking on, just this once
ollama ps                            # how much of the model is on the GPU
```

`gemma4:26b` is the default. It is a mixture-of-experts model, so only a few
billion of its parameters are active per token and it stays usable even when the
weights do not fit in VRAM and most layers run on the CPU, which is the normal
case on a laptop GPU. The first run downloads roughly 19GB, so allow time on a
throttled link. Pick something else with `-LlmModel`, for example
`-LlmModel gemma4:12b` on a machine with less memory.

To compare models on your own hardware before settling:

```powershell
pwsh -File .\verify-work-setup.ps1 -Benchmark
```

That reports tokens per second and the CPU/GPU split for each model and prints
the `ollama rm` command for the ones you do not keep. It never removes anything
itself.

**Privacy.** These are set as persistent user environment variables:

| Variable | Value | Why |
|---|---|---|
| `OLLAMA_HOST` | `127.0.0.1:11434` | loopback only, unreachable from the network |
| `OLLAMA_FLASH_ATTENTION` | `1` | faster attention kernels |
| `OLLAMA_KV_CACHE_TYPE` | `q8_0` | smaller KV cache, more context per GB |
| `OLLAMA_NUM_PARALLEL` | `1` | one request at a time |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | never hold two models in memory at once |

Leave **Expose Ollama to the network** switched off in Ollama's own settings,
and do not sign in to an Ollama account: this setup is entirely local and uses
no cloud models.

### Why the certificate step is needed

Zscaler terminates TLS with its own root CA. Tools that read the Windows trust
store (WinGet, .NET, Docker Desktop) inherit that trust automatically. Tools
that carry their own CA bundle do not, which is why npm, Azure CLI and
Neovim's Mason fail on an otherwise working machine.

| Variable | Bundle | Fixes |
|---|---|---|
| `NODE_EXTRA_CA_CERTS` | corporate roots only (additive) | node, npm, pnpm, yarn, vite |
| `REQUESTS_CA_BUNDLE` | full Windows store (replacing) | Azure CLI, Python requests |
| `CURL_CA_BUNDLE` | full Windows store | curl, Mason in Neovim |
| `SSL_CERT_FILE` | full Windows store | OpenSSL-based tools |
| `PIP_CERT` | full Windows store | pip |
| `UV_NATIVE_TLS` | the Windows store directly | uv, and the `llm` install |

Git is handled differently: `http.sslBackend=schannel` makes it read the
Windows store directly, so it needs no bundle at all.

TLS verification is never disabled. `NODE_EXTRA_CA_CERTS` gets the corporate
roots alone because it *adds* to Node's built-in trust; the others get the
full Windows store because they *replace* a tool's bundle, and a partial file
would break every non-inspected connection.

Bundles are written to `~/.config/certs/`. Re-run the script after a CA
rotation, or roll the variables back with:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\work-setup.ps1 -RemoveCertEnv
```

### Useful switches

| Switch | Effect |
|---|---|
| `-SkipInstalls` | Certificates and config only, for a locked-down machine |
| `-SkipCerts` | Terminal setup without touching trust settings |
| `-SkipConfig` | Installs and certificates only, leaving your config files alone |
| `-SkipLlm` | Skip Ollama, `uv`, `llm` and the model download |
| `-LlmModel` | Build `terminal-llm` from a different Ollama tag |
| `-ExtraCaSubject` | Extra root CA subject patterns for an in-house proxy |
| `-ProbeHost` | Hosts to TLS-probe when looking for the inspecting root CA |
| `-RemoveCertEnv` | Remove the certificate variables and exit |

`verify-work-setup.ps1` takes `-Benchmark` and `-BenchmarkModel`.

### Why this file is pure ASCII

Windows PowerShell 5.1 reads a script without a byte order mark as the ANSI
codepage, not UTF-8. `work-setup.ps1` writes out a Starship config full of
prompt glyphs, so a misread encoding turns the `>` chevron into `â¯` and every
comment rule into `â”€â”€` — in the *generated* files, where it is hard to trace
back.

Three things prevent that, and re-running the script repairs files that were
already written badly:

- the script body is pure ASCII, with prompt symbols written as TOML `\uXXXX`
  escapes and any glyph it prints built with `[char]::ConvertFromUtf32`
- it is saved with a UTF-8 BOM, so 5.1 cannot misread it even if a non-ASCII
  character sneaks back in
- `.gitattributes` marks `*.ps1` as `-text`, so Git never rewrites the bytes

### Notes

- Docker **builds** are not covered. A container has its own trust store, so
  an image that fetches over TLS needs the CA copied in
  (`COPY corporate-roots.pem /usr/local/share/ca-certificates/` then
  `update-ca-certificates`). Docker Desktop itself uses the Windows store.
- PowerShell 7 paints directory names with a solid blue background. The profile
  sets `$PSStyle.FileInfo.Directory` to bold blue text instead, matching `eza`
  on macOS.
- If Documents is redirected to OneDrive, the profile is still written where
  `pwsh` reads it from, and the script says so.
- The prompt shows the Azure subscription only if you set `disabled = false`
  under `[azure]` in `~/.config/starship.toml`. It is off by default so the
  subscription name stays out of screen shares.
- Existing files are backed up to `~/.config-backups/dotfiles-<timestamp>/`
  before replacement, and the Windows Terminal fragment adds a profile without
  rewriting `settings.json`.


## Windows (personal / new device)

Sets up a native Windows developer terminal with the same minimal Catppuccin
prompt as the Mac. Ghostty does not currently support Windows, so this setup
uses Windows Terminal with PowerShell 7 instead.

Open PowerShell in the cloned repository, then run:

```powershell
cd windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

Use `-SkipCodex` if you do not want the script to install Codex CLI.

### What gets installed

- **Terminal:** Windows Terminal with a dedicated transparent Catppuccin Mocha developer profile
- **Shell:** PowerShell 7 with PSReadLine history suggestions and Atuin search
- **Prompt:** the same minimal Starship layout with project, Git status, Node version and command duration
- **Font:** JetBrains Mono Nerd Font for prompt symbols
- **Core tools:** Git and Node.js LTS through WinGet
- **AI:** Codex CLI through npm after Node and npm are verified

### Terminal configuration

The editable source files live under [`windows/config`](windows/config):

| File | Installed to | Purpose |
|---|---|---|
| `Microsoft.PowerShell_profile.ps1` | `~/Documents/PowerShell/Microsoft.PowerShell_profile.ps1` | PSReadLine, Atuin and Starship startup |
| `starship.toml` | `~/.config/starship.toml` | Minimal prompt layout and Catppuccin colours |
| `atuin.toml` | `~/.config/atuin/config.toml` | History search and key behaviour |
| `windows-terminal.fragment.json` | `%LOCALAPPDATA%/Microsoft/Windows Terminal/Fragments/eddie-dotfiles/developer.json` | Adds the Developer PowerShell profile and Catppuccin colour scheme |

Existing config files are copied to
`~/.config-backups/dotfiles-<timestamp>/` before replacement. The Windows
Terminal fragment adds a new profile without rewriting the user's main
`settings.json`. The setup does not read, copy or modify Codex configuration or
credentials, and this repository does not track them.

### After running

1. Close and reopen Windows Terminal
2. Select **Developer PowerShell** from the new-tab menu
3. Optionally make it the default under **Settings > Startup**
4. Run `codex login` to connect ChatGPT
5. Run `atuin login` if you want history sync
