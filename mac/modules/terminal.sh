#!/usr/bin/env zsh
# ==============================================================================
#  Module: terminal
#
#  The shell and everything you look at: Ghostty, zsh with Oh My Zsh, the
#  Starship prompt, Atuin history, and the small command-line tools the shell
#  config expects. Installs no languages, runtimes, databases or GUI apps.
#
#  Run on its own:  ./modules/terminal.sh
# ==============================================================================

set -e
source "${${(%):-%x}:A:h}/../lib.sh"

MODULE_DESCRIPTION="Ghostty, zsh with Oh My Zsh, Starship, Atuin and the shell tools."
module_args "$@"

FORMULAE=(
  # Shell and prompt
  zsh
  starship  # Prompt
  atuin     # Searchable shell history

  # Version control
  git

  # Search and navigation
  fzf       # Fuzzy finder
  ripgrep   # Fast grep, and what fzf searches with
  fd        # Fast find
  zoxide    # Smarter cd

  # Everyday utilities
  bat       # Better cat
  eza       # Better ls
  jq        # JSON processor
  tree
  htop
  wget
)

CASKS=(
  ghostty
  font-jetbrains-mono-nerd-font
)

info "Setting up the terminal..."
ensure_homebrew
brew_install_formulae "${FORMULAE[@]}"
brew_install_casks "${CASKS[@]}"

# ── Git identity ──────────────────────────────────────────────────────────────
# Only ask for what is not already configured, so re-runs stay quiet and a
# machine that already has an identity is left alone.
info "Configuring Git..."

git_name="$(git config --global user.name 2>/dev/null || true)"
git_email="$(git config --global user.email 2>/dev/null || true)"

if ! dry_run && [ -t 0 ]; then
  if [ -z "$git_name" ]; then
    read "git_name?  Enter your Git name:  "
  fi
  if [ -z "$git_email" ]; then
    read "git_email?  Enter your Git email: "
  fi
fi

if dry_run; then
  info "[dry run] configure git identity, init.defaultBranch, pull.rebase"
elif [ -n "$git_name" ] && [ -n "$git_email" ]; then
  git config --global user.name "$git_name"
  git config --global user.email "$git_email"
  git config --global init.defaultBranch main
  git config --global pull.rebase false
  # Only claim an editor that is actually installed — nvim comes with the dev
  # module, which may not have been selected.
  if command -v nvim &>/dev/null; then
    git config --global core.editor "nvim"
  fi
  success "Git configured for $git_name."
else
  warn "Git identity not set."
  next_step "Set your Git identity: git config --global user.name \"…\" && git config --global user.email \"…\""
fi

# ── Oh My Zsh ─────────────────────────────────────────────────────────────────
info "Checking Oh My Zsh..."
if dry_run; then
  info "[dry run] install Oh My Zsh and its plugins"
else
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    info "Installing Oh My Zsh..."
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    success "Oh My Zsh already installed."
  fi

  # ── Zsh plugins ─────────────────────────────────────────────────────────────
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
if dry_run; then
  info "[dry run] run the fzf shell integration installer"
else
  "$(brew --prefix)/opt/fzf/install" --no-bash --no-fish --no-update-rc --completion --key-bindings 2>/dev/null || true
  success "fzf shell integration done."
fi

next_step "Quit and reopen Ghostty, then run: exec zsh -l"

success "Terminal module done."
