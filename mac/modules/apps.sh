#!/usr/bin/env zsh
# ==============================================================================
#  Module: apps
#
#  The GUI applications and the one SDK that is not a command-line runtime.
#  Nothing here is needed by the terminal or dev modules.
#
#  Run on its own:  ./modules/apps.sh
# ==============================================================================

set -e
source "${${(%):-%x}:A:h}/../lib.sh"

MODULE_DESCRIPTION="1Password, Raycast, Rectangle, DBeaver, the .NET SDK and Codex."
module_args "$@"

CASKS=(
  1password
  codex
  dbeaver-community
  dotnet-sdk
  raycast
  rectangle
)

info "Installing applications..."
ensure_homebrew
brew_install_casks "${CASKS[@]}"

# The zshrc points SSH_AUTH_SOCK at 1Password's agent socket, but only once the
# socket exists — so enabling the agent is what actually turns SSH on.
next_step "Open 1Password and enable the SSH agent in its settings"
next_step "Sign in to Codex: codex login"

success "Apps module done."
