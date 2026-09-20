#!/usr/bin/env zsh
# ==============================================================================
#  Module: dev
#
#  Languages, runtimes, editor and the local services a project usually needs:
#  Node, Go, Python, Rust, Neovim with LazyVim, Docker, MySQL, Postgres and the
#  AWS CLI. Assumes the terminal module for shell config, but does not require
#  it.
#
#  Run on its own:  ./modules/dev.sh
# ==============================================================================

set -e
source "${${(%):-%x}:A:h}/../lib.sh"

MODULE_DESCRIPTION="Node, Go, Python, Rust, Neovim with LazyVim, Docker, databases and the AWS CLI."
module_args "$@"

FORMULAE=(
  # Version control tooling
  gh
  git-flow-avh
  lazygit

  # Editor
  neovim

  # Languages and runtimes
  nvm
  go
  python@3.13
  rustup

  # Containers
  docker
  docker-completion
  docker-compose

  # Databases
  mysql
  postgresql@15

  # Cloud
  awscli
)

info "Setting up the development environment..."
ensure_homebrew
brew_install_formulae "${FORMULAE[@]}"

# ── NVM + Node ────────────────────────────────────────────────────────────────
info "Setting up NVM and Node v23..."

if dry_run; then
  info "[dry run] nvm install 23, set as default, npm install -g pnpm yarn"
else
  export NVM_DIR="$HOME/.nvm"
  [ -s "$(brew --prefix)/opt/nvm/nvm.sh" ] && source "$(brew --prefix)/opt/nvm/nvm.sh"

  if command -v nvm &>/dev/null; then
    nvm install 23
    nvm use 23
    nvm alias default 23
    success "Node v23 installed and set as default."

    # Needs the node from the lines above, so it stays inside this branch.
    info "Installing global npm packages (pnpm, yarn)..."
    npm install -g pnpm yarn
    success "pnpm and yarn installed globally."
  else
    warn "nvm not available in this shell session."
    next_step "Restart your terminal, then run: nvm install 23"
  fi
fi

# ── Rust ──────────────────────────────────────────────────────────────────────
info "Setting up Rust via rustup..."

if dry_run; then
  info "[dry run] rustup-init -y --no-modify-path"
elif command -v rustup-init &>/dev/null; then
  rustup-init -y --no-modify-path
  source "$HOME/.cargo/env" 2>/dev/null || true
  success "Rust (stable) installed."
else
  warn "rustup-init not found."
  next_step "Restart your terminal, then run: rustup-init"
fi

if dry_run; then
  info "[dry run] write the LazyVim config to ~/.config/nvim"
else
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
fi

next_step "Open nvim — LazyVim plugins install automatically on first launch"
next_step "Configure AWS credentials: aws configure"
next_step "Start Postgres if you need it: brew services start postgresql@15"
next_step "Start MySQL if you need it: brew services start mysql"

success "Dev module done."
