#!/usr/bin/env zsh
# =============================================================================
#  Mac Dev Environment Setup
#
#  Usage:
#    chmod +x setup.sh && ./setup.sh
#
#  What this installs:
#    - Homebrew + formulae (git, neovim, go, node/nvm, rust, lazygit,
#      ripgrep, fd, fzf, jq, gh, bat, eza, zoxide, awscli, docker, ...)
#    - Homebrew casks (Warp, Rectangle, DBeaver, Raycast, 1Password, ...)
#    - Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting
#    - Custom eastwood zsh theme
#    - LazyVim (Neovim distribution)
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
echo "${BOLD}Mac Dev Environment Setup${RESET}"
echo "────────────────────────────────────────"
echo ""

# ── Collect user info up front ────────────────────────────────────────────────
info "Git configuration"
read "GIT_NAME?  Enter your Git name:  "
read "GIT_EMAIL?  Enter your Git email: "
echo ""

# ── Homebrew ──────────────────────────────────────────────────────────────────
info "Checking Homebrew..."
if ! command -v brew &>/dev/null; then
  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  success "Homebrew already installed."
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

info "Updating Homebrew..."
brew update --quiet

# ── Homebrew Formulae ─────────────────────────────────────────────────────────
info "Installing Homebrew formulae..."

FORMULAE=(
  # Core dev tools
  git
  git-flow-avh
  gh
  lazygit

  # Editor
  neovim
  ripgrep   # LazyVim live grep
  fd        # LazyVim file finder
  fzf       # Fuzzy finder (shell + vim)

  # Shell utilities
  bat       # Better cat
  eza       # Better ls
  zoxide    # Smarter cd
  jq        # JSON processor
  htop
  tree
  wget

  # Languages & runtimes
  go
  nvm
  python@3.13
  rustup

  # Databases
  mysql
  postgresql@15

  # Cloud & containers
  awscli
  docker
  docker-completion
  docker-compose

  # Shell
  zsh
)

for formula in "${FORMULAE[@]}"; do
  if brew list --formula "$formula" &>/dev/null; then
    success "$formula already installed."
  else
    info "Installing $formula..."
    brew install "$formula"
  fi
done

# ── Homebrew Casks ────────────────────────────────────────────────────────────
info "Installing Homebrew casks..."

CASKS=(
  1password
  dbeaver-community
  dotnet-sdk
  font-jetbrains-mono-nerd-font
  raycast
  rectangle
  warp
)

for cask in "${CASKS[@]}"; do
  if brew list --cask "$cask" &>/dev/null; then
    success "$cask already installed."
  else
    info "Installing $cask..."
    brew install --cask "$cask"
  fi
done

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

# ── Homebrew ──────────────────────────────────────────────────────────────────
export PATH="/opt/homebrew/bin:$PATH"

# ── NVM ───────────────────────────────────────────────────────────────────────
export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && source "/opt/homebrew/opt/nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && source "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"

# ── Python ────────────────────────────────────────────────────────────────────
alias python="/opt/homebrew/bin/python3"
alias pip="/opt/homebrew/bin/pip3"

# ── Better shell tools ────────────────────────────────────────────────────────
alias ls="eza --icons --group-directories-first"
alias ll="eza -la --icons --group-directories-first"
alias cat="bat"

# fzf shell integration
[ -f "/opt/homebrew/opt/fzf/shell/completion.zsh" ] && source "/opt/homebrew/opt/fzf/shell/completion.zsh"
[ -f "/opt/homebrew/opt/fzf/shell/key-bindings.zsh" ] && source "/opt/homebrew/opt/fzf/shell/key-bindings.zsh"

# zoxide (smarter cd — use 'z' instead of 'cd')
eval "$(zoxide init zsh)"

# ── 1Password SSH Agent ───────────────────────────────────────────────────────
# Requires 1Password to be installed with the SSH agent enabled in its settings.
# Comment out if you are not using 1Password.
export SSH_AUTH_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/agent.sock"
ZSHRC

success "~/.zshrc written."

# ── .zprofile ─────────────────────────────────────────────────────────────────
info "Writing ~/.zprofile..."

cat > "$HOME/.zprofile" << 'ZPROFILE'
eval "$(/opt/homebrew/bin/brew shellenv)"
ZPROFILE

success "~/.zprofile written."

# ── fzf shell integration ─────────────────────────────────────────────────────
info "Setting up fzf shell integration..."
"$(brew --prefix)/opt/fzf/install" --no-bash --no-fish --no-update-rc --completion --key-bindings 2>/dev/null || true
success "fzf shell integration done."

# ── NVM + Node ────────────────────────────────────────────────────────────────
info "Setting up NVM and Node v23..."

export NVM_DIR="$HOME/.nvm"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && source "/opt/homebrew/opt/nvm/nvm.sh"

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

if command -v rustup-init &>/dev/null; then
  rustup-init -y --no-modify-path
  source "$HOME/.cargo/env" 2>/dev/null || true
  success "Rust (stable) installed."
else
  warn "rustup-init not found — run 'rustup-init' manually after restarting your terminal."
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

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo "${GREEN}${BOLD}  All done! A few manual steps remain:${RESET}"
echo "${GREEN}${BOLD}════════════════════════════════════════${RESET}"
echo ""
echo "  1. Restart your terminal (or: source ~/.zshrc)"
echo "  2. Open nvim — LazyVim plugins install automatically on first launch"
echo "  3. Open 1Password and enable the SSH agent in its settings"
echo "  4. Configure AWS credentials:      aws configure"
echo "  5. Start Postgres (if needed):     brew services start postgresql@15"
echo "  6. Start MySQL (if needed):        brew services start mysql"
echo ""
