#!/usr/bin/env bash
# =============================================================================
#  Linux Dev Environment Setup (minimal base — Ubuntu/Debian)
#
#  Usage:
#    chmod +x setup.sh && ./setup.sh
#
#  What this installs:
#    - Core apt packages (git, neovim, zsh, ripgrep, fd, fzf, bat, jq, ...)
#    - lazygit (latest binary release)
#    - gh (GitHub CLI via apt)
#    - zoxide (via install script)
#    - Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting
#    - Custom eastwood zsh theme
#    - LazyVim (Neovim distribution)
#    - Go (latest from golang.org)
#    - Node via NVM (v23)
#    - Rust via rustup (stable)
#    - Global npm packages: pnpm, yarn
# =============================================================================

set -e

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

info()    { echo "${CYAN}${BOLD}==> $*${RESET}"; }
success() { echo "${GREEN}${BOLD}✔  $*${RESET}"; }
warn()    { echo "${YELLOW}${BOLD}!  $*${RESET}"; }

echo ""
echo "${BOLD}Linux Dev Environment Setup${RESET}"
echo "────────────────────────────────────────"
echo ""

# ── Collect user info up front ────────────────────────────────────────────────
info "Git configuration"
read -rp "  Enter your Git name:  " GIT_NAME
read -rp "  Enter your Git email: " GIT_EMAIL
echo ""

# ── apt packages ──────────────────────────────────────────────────────────────
info "Updating apt..."
sudo apt update -qq

info "Installing apt packages..."

PACKAGES=(
  # Core dev tools
  git
  curl
  wget
  build-essential

  # Editor
  neovim
  ripgrep
  fd-find
  fzf

  # Shell
  zsh

  # Shell utilities
  bat
  htop
  tree
  jq
  unzip
  zip

  # Languages & runtimes
  golang-go
)

for pkg in "${PACKAGES[@]}"; do
  if dpkg -s "$pkg" &>/dev/null; then
    success "$pkg already installed."
  else
    info "Installing $pkg..."
    sudo apt install -y "$pkg"
  fi
done

# Symlink fd-find → fd if needed
if ! command -v fd &>/dev/null && command -v fdfind &>/dev/null; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
  success "fd symlinked."
fi

# Symlink batcat → bat if needed
if ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
  mkdir -p "$HOME/.local/bin"
  ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
  success "bat symlinked."
fi

# ── GitHub CLI ────────────────────────────────────────────────────────────────
info "Checking gh (GitHub CLI)..."
if ! command -v gh &>/dev/null; then
  info "Installing gh..."
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
  sudo apt update -qq && sudo apt install -y gh
  success "gh installed."
else
  success "gh already installed."
fi

# ── lazygit ───────────────────────────────────────────────────────────────────
info "Checking lazygit..."
if ! command -v lazygit &>/dev/null; then
  info "Installing lazygit..."
  LAZYGIT_VERSION=$(curl -s https://api.github.com/repos/jesseduffield/lazygit/releases/latest \
    | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')
  curl -sLo /tmp/lazygit.tar.gz \
    "https://github.com/jesseduffield/lazygit/releases/latest/download/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
  tar -xf /tmp/lazygit.tar.gz -C /tmp lazygit
  sudo install /tmp/lazygit /usr/local/bin/lazygit
  rm /tmp/lazygit /tmp/lazygit.tar.gz
  success "lazygit installed."
else
  success "lazygit already installed."
fi

# ── zoxide ────────────────────────────────────────────────────────────────────
info "Checking zoxide..."
if ! command -v zoxide &>/dev/null; then
  info "Installing zoxide..."
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  success "zoxide installed."
else
  success "zoxide already installed."
fi

# ── eza ───────────────────────────────────────────────────────────────────────
info "Checking eza..."
if ! command -v eza &>/dev/null; then
  info "Installing eza..."
  sudo mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
    | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
    | sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null
  sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  sudo apt update -qq && sudo apt install -y eza
  success "eza installed."
else
  success "eza already installed."
fi

# ── Git Config ────────────────────────────────────────────────────────────────
info "Configuring Git..."

git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global init.defaultBranch main
git config --global pull.rebase false
git config --global core.editor "nvim"

success "Git configured for $GIT_NAME."

# ── Oh My Zsh ─────────────────────────────────────────────────────────────────
info "Checking Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  info "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  success "Oh My Zsh already installed."
fi

# ── Zsh Plugins ───────────────────────────────────────────────────────────────
info "Installing zsh plugins..."

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions \
    "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
  success "zsh-autosuggestions installed."
else
  success "zsh-autosuggestions already installed."
fi

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting \
    "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
  success "zsh-syntax-highlighting installed."
else
  success "zsh-syntax-highlighting already installed."
fi

# ── Custom Zsh Theme (eastwood) ───────────────────────────────────────────────
info "Writing eastwood zsh theme..."
mkdir -p "$HOME/.zsh/themes"

cat > "$HOME/.zsh/themes/eastwood.zsh-theme" << 'THEME'
ZSH_THEME_GIT_PROMPT_PREFIX="%{$reset_color%}%{$fg[green]%}["
ZSH_THEME_GIT_PROMPT_SUFFIX="]%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%}*%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""

git_custom_status() {
  local cb=$(git_current_branch)
  if [ -n "$cb" ]; then
    echo "$(parse_git_dirty)$ZSH_THEME_GIT_PROMPT_PREFIX$(git_current_branch)$ZSH_THEME_GIT_PROMPT_SUFFIX"
  fi
}

PROMPT='$(git_custom_status)%{$fg[cyan]%}[%~% ]%{$reset_color%}%B$%b '
THEME

success "eastwood theme written."

# ── .zshrc ────────────────────────────────────────────────────────────────────
info "Writing ~/.zshrc..."

cat > "$HOME/.zshrc" << 'ZSHRC'
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="eastwood"

plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh
source ~/.zsh/themes/eastwood.zsh-theme
source ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# ── Local bin ─────────────────────────────────────────────────────────────────
export PATH="$HOME/.local/bin:$PATH"

# ── Go ────────────────────────────────────────────────────────────────────────
export PATH="$PATH:/usr/local/go/bin"

# ── NVM ───────────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && source "$NVM_DIR/bash_completion"

# ── Rust ──────────────────────────────────────────────────────────────────────
[ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"

# ── Better shell tools ────────────────────────────────────────────────────────
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first"
alias cat="bat"

# fzf shell integration
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh

# zoxide (smarter cd — use 'z' instead of 'cd')
eval "$(zoxide init zsh)"
ZSHRC

success "~/.zshrc written."

# ── NVM + Node ────────────────────────────────────────────────────────────────
info "Setting up NVM and Node v23..."

export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi

[ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

if command -v nvm &>/dev/null; then
  nvm install 23
  nvm use 23
  nvm alias default 23
  success "Node v23 installed and set as default."

  info "Installing global npm packages (pnpm, yarn)..."
  npm install -g pnpm yarn
  success "pnpm and yarn installed globally."
else
  warn "nvm not available in this shell session."
  warn "After restarting your terminal, run: nvm install 23"
fi

# ── Rust ──────────────────────────────────────────────────────────────────────
info "Setting up Rust via rustup..."

if ! command -v rustup &>/dev/null; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
  source "$HOME/.cargo/env" 2>/dev/null || true
  success "Rust (stable) installed."
else
  success "Rust already installed."
fi

# ── LazyVim ───────────────────────────────────────────────────────────────────
info "Setting up LazyVim (Neovim config)..."

NVIM_CONFIG="$HOME/.config/nvim"

if [ -d "$NVIM_CONFIG" ]; then
  warn "~/.config/nvim already exists — skipping to avoid overwriting."
  warn "To start fresh: rm -rf ~/.config/nvim ~/.local/share/nvim ~/.cache/nvim"
else
  mkdir -p "$NVIM_CONFIG/lua/config"
  mkdir -p "$NVIM_CONFIG/lua/plugins"

  cat > "$NVIM_CONFIG/init.lua" << 'EOF'
-- Bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
EOF

  cat > "$NVIM_CONFIG/lua/config/lazy.lua" << 'EOF'
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  local lazyrepo = "https://github.com/folke/lazy.nvim.git"
  local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
  if vim.v.shell_error ~= 0 then
    vim.api.nvim_echo({
      { "Failed to clone lazy.nvim:\n", "ErrorMsg" },
      { out, "WarningMsg" },
      { "\nPress any key to exit..." },
    }, true, {})
    vim.fn.getchar()
    os.exit(1)
  end
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { "LazyVim/LazyVim", import = "lazyvim.plugins" },
    { import = "plugins" },
  },
  defaults = {
    lazy = false,
    version = false,
  },
  install = { colorscheme = { "tokyonight", "habamax" } },
  checker = {
    enabled = true,
    notify = false,
  },
  performance = {
    rtp = {
      disabled_plugins = {
        "gzip",
        "tarPlugin",
        "tohtml",
        "tutor",
        "zipPlugin",
      },
    },
  },
})
EOF

  cat > "$NVIM_CONFIG/lua/config/options.lua" << 'EOF'
-- Options are automatically loaded before lazy.nvim startup
-- Add any additional options here
EOF

  cat > "$NVIM_CONFIG/lua/config/keymaps.lua" << 'EOF'
-- Keymaps are automatically loaded on the VeryLazy event
-- Add any additional keymaps here
EOF

  cat > "$NVIM_CONFIG/lua/config/autocmds.lua" << 'EOF'
-- Autocmds are automatically loaded on the VeryLazy event
-- Add any additional autocmds here
EOF

  cat > "$NVIM_CONFIG/lua/plugins/init.lua" << 'EOF'
-- Add your custom plugins here
return {}
EOF

  success "LazyVim config written to ~/.config/nvim"
  info "Plugins will auto-install on first launch of nvim."
fi

# ── Default shell ─────────────────────────────────────────────────────────────
info "Setting zsh as default shell..."
if [ "$SHELL" != "$(command -v zsh)" ]; then
  chsh -s "$(command -v zsh)"
  success "Default shell set to zsh."
else
  success "zsh is already the default shell."
fi

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  All done! A few manual steps remain:${RESET}"
echo "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo ""
echo "  1. Restart your terminal (or: exec zsh)"
echo "  2. Open nvim — LazyVim plugins install automatically on first launch"
echo "  3. Run: nvm install 23  (if Node wasn't installed above)"
echo "  4. Configure AWS credentials (if needed): aws configure"
echo ""
