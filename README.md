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
- **AI** — Codex CLI with portable model, reasoning and personality defaults
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
| `codex/config.toml` | `~/.codex/config.toml` | Portable Codex defaults; never credentials |

Existing config files are copied to `~/.config-backups/dotfiles-<timestamp>/` before replacement. An existing Codex config is preserved because the desktop app may add machine-specific plugin settings; use the tracked file as a reviewable template in that case. Codex credentials (`~/.codex/auth.json`) are deliberately excluded.

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
