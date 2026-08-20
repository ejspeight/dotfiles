# dotfiles

Personal machine setup scripts for getting a new machine up and running.

## Mac

Sets up a full dev environment including Ghostty, Codex, a minimal Catppuccin Starship prompt, searchable shell history, Neovim (LazyVim), Node, .NET, Rust, Go, and more.

```bash
cd mac
chmod +x setup.sh && ./setup.sh
```

### What gets installed

- **Homebrew** — package manager + all formulae
- **Neovim** — with [LazyVim](https://www.lazyvim.org) (plugins auto-install on first launch)
- **Terminal** — Ghostty with Catppuccin Mocha, JetBrains Mono Nerd Font, transparency and blur
- **Prompt** — minimal Starship layout with project, Git status, Node version and command duration
- **Shell** — Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting, Atuin history and command-only typo correction
- **Languages** — Node (via nvm), Go, Rust (via rustup), Python, .NET SDK
- **Shell tools** — fzf, ripgrep, fd, bat, eza, zoxide, jq, lazygit, gh
- **AI** — Codex CLI application; its configuration and credentials remain local
- **Apps** — Ghostty, Codex, Warp, Raycast, Rectangle, DBeaver, 1Password

### Terminal configuration

The editable source files live under [`mac/config`](mac/config):

| File | Installed to | Purpose |
|---|---|---|
| `zshrc` | `~/.zshrc` | Shell plugins, aliases, Atuin and Starship startup |
| `zprofile` | `~/.zprofile` | Homebrew environment for login shells |
| `starship.toml` | `~/.config/starship.toml` | Minimal prompt layout and Catppuccin colours |
| `atuin.toml` | `~/.config/atuin/config.toml` | History search and key behaviour |
| `ghostty/config.ghostty` | `~/Library/Application Support/com.mitchellh.ghostty/config.ghostty` | Font, theme, transparency and window behaviour |

Existing config files are copied to `~/.config-backups/dotfiles-<timestamp>/`
before replacement. The setup does not read, copy or modify Codex configuration
or credentials, and this repository does not track them.

### After running

1. Quit and reopen Ghostty, then run `exec zsh -l`
2. Run `codex login` and sign in with ChatGPT
3. Open `nvim` — LazyVim plugins install automatically
4. Enable the SSH agent in 1Password settings
5. Run `aws configure` to set up AWS credentials

## Linux

Minimal base setup for Ubuntu/Debian. Installs core tools via apt, then builds up the same shell environment as Mac.

```bash
cd linux
chmod +x setup.sh && ./setup.sh
```

### What gets installed

- **apt packages** — git, neovim, zsh, ripgrep, fd, fzf, bat, htop, jq, Go, and more
- **lazygit** — latest binary from GitHub releases
- **gh** — GitHub CLI via official apt repo
- **eza** — better `ls` via eza apt repo
- **zoxide** — smarter `cd`
- **Neovim** — with [LazyVim](https://www.lazyvim.org) (plugins auto-install on first launch)
- **Oh My Zsh** — with zsh-autosuggestions, zsh-syntax-highlighting, eastwood theme
- **Languages** — Node (via nvm), Rust (via rustup), Go
- **Shell tools** — fzf, ripgrep, fd, bat, eza, zoxide, jq, lazygit, gh

### After running

1. Restart your terminal (or `exec zsh`)
2. Open `nvim` — LazyVim plugins install automatically
3. Run `nvm install 23` if Node wasn't set up during the script

## Windows

Sets up a native Windows developer terminal with the same minimal Catppuccin
prompt as the Mac. Ghostty does not currently support Windows, so this setup
uses Windows Terminal with PowerShell 7 instead. It does not modify or remove
Warp.

Open PowerShell in the cloned repository, then run:

```powershell
cd windows
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

Use `-SkipCodex` if you do not want the script to install Codex CLI.

### What gets installed

- **Terminal** — Windows Terminal with a dedicated transparent Catppuccin Mocha developer profile
- **Shell** — PowerShell 7 with PSReadLine history suggestions and Atuin search
- **Prompt** — the same minimal Starship layout with project, Git status, Node version and command duration
- **Font** — JetBrains Mono Nerd Font for prompt symbols
- **Core tools** — Git and Node.js LTS through WinGet
- **AI** — Codex CLI through npm after Node and npm are verified

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
