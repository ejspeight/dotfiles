# dotfiles

Personal machine setup scripts for getting a new Mac up and running.

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
