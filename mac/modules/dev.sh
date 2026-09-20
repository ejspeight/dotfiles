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

# -- Neovim (LazyVim) ----------------------------------------------------------
info "Installing the Neovim config..."

NVIM_CONFIG="$HOME/.config/nvim"

# A config that is not this one is about to have its entry points replaced.
# install_config backs them up first, but say so before doing it.
if [ -f "$NVIM_CONFIG/init.lua" ] && ! grep -q 'config.lazy' "$NVIM_CONFIG/init.lua" 2>/dev/null; then
  warn "~/.config/nvim holds a Neovim config that is not this one."
  warn "init.lua and lua/config/lazy.lua will be replaced (backed up first)."
fi

# The bootstrap is machinery the repo owns, so it is replaced on every run, the
# same way ~/.zshrc is. That is what lets a fix here reach a machine that is
# already set up.
install_config "$CONFIG_DIR/nvim/init.lua"            "$NVIM_CONFIG/init.lua"
install_config "$CONFIG_DIR/nvim/lua/config/lazy.lua" "$NVIM_CONFIG/lua/config/lazy.lua"

# These four are meant to be edited. Seed them once, then leave them alone, so
# your own options and keymaps survive a re-run.
seed_config "$CONFIG_DIR/nvim/lua/config/options.lua"  "$NVIM_CONFIG/lua/config/options.lua"
seed_config "$CONFIG_DIR/nvim/lua/config/keymaps.lua"  "$NVIM_CONFIG/lua/config/keymaps.lua"
seed_config "$CONFIG_DIR/nvim/lua/config/autocmds.lua" "$NVIM_CONFIG/lua/config/autocmds.lua"
seed_config "$CONFIG_DIR/nvim/lua/plugins/init.lua"    "$NVIM_CONFIG/lua/plugins/init.lua"

next_step "Open nvim — LazyVim plugins install automatically on first launch"
next_step "Configure AWS credentials: aws configure"
next_step "Start Postgres if you need it: brew services start postgresql@15"
next_step "Start MySQL if you need it: brew services start mysql"

success "Dev module done."
