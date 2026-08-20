#!/usr/bin/env zsh
# =============================================================================
#  Mac Dev Environment Setup
#
#  Usage:
#    chmod +x setup.sh && ./setup.sh
#
#  What this installs:
#    - Homebrew + formulae (git, neovim, go, node/nvm, rust, lazygit,
#      ripgrep, fd, fzf, jq, gh, bat, eza, zoxide, Atuin, Starship, ...)
#    - Homebrew casks (Ghostty, Codex, Rectangle, 1Password, ...)
#    - Oh My Zsh + zsh-autosuggestions + zsh-syntax-highlighting
#    - Minimal Catppuccin Ghostty and Starship configuration
#    - LazyVim (Neovim distribution)
#    - Node via NVM (v23)
#    - Rust via rustup (stable)
#    - Global npm packages: pnpm, yarn
# =============================================================================

set -e

readonly SCRIPT_DIR="${0:A:h}"
readonly CONFIG_DIR="$SCRIPT_DIR/config"
readonly BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP_DIR="$HOME/.config-backups/dotfiles-$BACKUP_STAMP"

# ── Colours ───────────────────────────────────────────────────────────────────
BOLD=$(tput bold)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
CYAN=$(tput setaf 6)
RESET=$(tput sgr0)

info()    { echo "${CYAN}${BOLD}==> $*${RESET}"; }
success() { echo "${GREEN}${BOLD}✔  $*${RESET}"; }
warn()    { echo "${YELLOW}${BOLD}!  $*${RESET}"; }

install_config() {
  local source_file="$1"
  local target_file="$2"
  local mode="${3:-0644}"

  if [ ! -f "$source_file" ]; then
    warn "Missing config asset: $source_file"
    return 1
  fi

  if [ -e "$target_file" ] || [ -L "$target_file" ]; then
    local relative_path="${target_file#$HOME/}"
    local backup_file="$BACKUP_DIR/$relative_path"
    mkdir -p "${backup_file:h}"
    cp -pL "$target_file" "$backup_file"
    [ -L "$target_file" ] && rm "$target_file"
  fi

  mkdir -p "${target_file:h}"
  cp "$source_file" "$target_file"
  chmod "$mode" "$target_file"
}

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
  atuin
  starship
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
  codex
  dbeaver-community
  dotnet-sdk
  font-jetbrains-mono-nerd-font
  ghostty
  raycast
  rectangle
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

# ── Terminal configuration ────────────────────────────────────────────────────
info "Installing terminal configuration..."

install_config "$CONFIG_DIR/zshrc" "$HOME/.zshrc"
install_config "$CONFIG_DIR/zprofile" "$HOME/.zprofile"
install_config "$CONFIG_DIR/starship.toml" "$HOME/.config/starship.toml"
install_config "$CONFIG_DIR/atuin.toml" "$HOME/.config/atuin/config.toml" 0600
install_config \
  "$CONFIG_DIR/ghostty/config.ghostty" \
  "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"

success "Terminal configuration installed."

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
echo "  1. Quit and reopen Ghostty, then run: exec zsh -l"
echo "  2. Sign in to Codex:                 codex login"
echo "  3. Open nvim — LazyVim plugins install automatically on first launch"
echo "  4. Open 1Password and enable the SSH agent in its settings"
echo "  5. Configure AWS credentials:        aws configure"
echo "  6. Start Postgres (if needed):       brew services start postgresql@15"
echo "  7. Start MySQL (if needed):          brew services start mysql"
if [ -d "$BACKUP_DIR" ]; then
  echo "  8. Previous config backups:          $BACKUP_DIR"
fi
echo ""
