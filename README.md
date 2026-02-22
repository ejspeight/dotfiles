# dotfiles

Personal machine setup scripts for getting a new machine up and running.

## Mac

Sets up a full dev environment including Homebrew, Neovim (LazyVim), Oh My Zsh, Node, .NET, Rust, Go, and more.

```bash
cd mac
chmod +x setup.sh && ./setup.sh
```

### What gets installed

- **Homebrew** — package manager + all formulae
- **Neovim** — with [LazyVim](https://www.lazyvim.org) (plugins auto-install on first launch)
- **Oh My Zsh** — with zsh-autosuggestions, zsh-syntax-highlighting, eastwood theme
- **Languages** — Node (via nvm), Go, Rust (via rustup), Python, .NET SDK
- **Shell tools** — fzf, ripgrep, fd, bat, eza, zoxide, jq, lazygit, gh
- **Apps** — Warp, Raycast, Rectangle, DBeaver, 1Password

### After running

1. Restart your terminal
2. Open `nvim` — LazyVim plugins install automatically
3. Enable the SSH agent in 1Password settings
4. Run `aws configure` to set up AWS credentials

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
