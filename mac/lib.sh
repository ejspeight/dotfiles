#!/usr/bin/env zsh
# ==============================================================================
#  Shared helpers for the Mac setup modules.
#
#  Every module sources this file, so each one runs standalone as well as from
#  setup.sh. Values that must be shared across a multi-module run (the backup
#  directory, the next-steps list) are created here only if the caller has not
#  already exported them.
# ==============================================================================

# Sourcing twice is harmless but pointless.
[ -n "$DOTFILES_LIB_LOADED" ] && return 0
DOTFILES_LIB_LOADED=1

# This file's own directory, not the caller's: a module in mac/modules/ still
# has to find mac/config/.
DOTFILES_MAC_DIR="${${(%):-%x}:A:h}"
CONFIG_DIR="$DOTFILES_MAC_DIR/config"
MODULES_DIR="$DOTFILES_MAC_DIR/modules"

# ── Colours ───────────────────────────────────────────────────────────────────
# Only when writing to a terminal, so --dry-run output pipes cleanly.
if [ -t 1 ]; then
  BOLD="$(tput bold)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  CYAN="$(tput setaf 6)"
  RESET="$(tput sgr0)"
else
  BOLD="" GREEN="" YELLOW="" CYAN="" RESET=""
fi

info()    { echo "${CYAN}${BOLD}==> $*${RESET}"; }
success() { echo "${GREEN}${BOLD}✔  $*${RESET}"; }
warn()    { echo "${YELLOW}${BOLD}!  $*${RESET}"; }

# ── Dry run ───────────────────────────────────────────────────────────────────
# Prints what would happen instead of doing it. Lets the whole flow be tested
# without installing anything.
dry_run() { [ -n "$DOTFILES_DRY_RUN" ]; }

# ── Backups ───────────────────────────────────────────────────────────────────
# One timestamped directory per run, shared by every module setup.sh invokes.
if [ -z "$DOTFILES_BACKUP_DIR" ]; then
  export DOTFILES_BACKUP_DIR="$HOME/.config-backups/dotfiles-$(date +%Y%m%d-%H%M%S)"
fi

# ── Next steps ────────────────────────────────────────────────────────────────
# Modules append the things a human still has to do. setup.sh creates and
# exports the file so a multi-module run prints one correctly numbered list; a
# module run on its own creates its own and prints it on exit.
if [ -z "$DOTFILES_STEPS_FILE" ]; then
  export DOTFILES_STEPS_FILE="$(mktemp)"
  DOTFILES_STEPS_OWNER=1
fi

next_step() { print -r -- "$*" >> "$DOTFILES_STEPS_FILE"; }

print_next_steps() {
  local -a steps
  [ -s "$DOTFILES_STEPS_FILE" ] && steps=("${(@f)$(<"$DOTFILES_STEPS_FILE")}")

  echo ""
  echo "${BOLD}Next steps${RESET}"
  if (( ${#steps} == 0 )); then
    echo "  Nothing to do — you are ready to go."
  else
    local index=1
    local step
    for step in "${steps[@]}"; do
      printf '  %d. %s\n' "$index" "$step"
      (( index++ ))
    done
  fi

  if [ -d "$DOTFILES_BACKUP_DIR" ]; then
    echo ""
    echo "  Previous config backed up to: $DOTFILES_BACKUP_DIR"
  fi
  echo ""
}

dotfiles_finish() {
  # Set by the --help and bad-argument paths: those are not runs, so they
  # should not print a next-steps block. A flag rather than `trap - EXIT`,
  # because a trap set inside a zsh function is local to that function.
  if [ -z "$DOTFILES_SUPPRESS_STEPS" ]; then
    print_next_steps
  fi
  rm -f "$DOTFILES_STEPS_FILE"
}

# Only the process that created the list is responsible for printing it.
if [ -n "$DOTFILES_STEPS_OWNER" ]; then
  trap dotfiles_finish EXIT
fi

# ── Module arguments ──────────────────────────────────────────────────────────
# Every module accepts the same flags. Without this, a module invoked with an
# unrecognised option would silently ignore it and start installing.
module_args() {
  while (( $# )); do
    case "$1" in
      -n|--dry-run)
        export DOTFILES_DRY_RUN=1
        ;;
      -h|--help)
        echo "Usage: ${ZSH_SCRIPT:t} [--dry-run]"
        echo ""
        echo "${MODULE_DESCRIPTION:-A dotfiles setup module.}"
        echo ""
        echo "  -n, --dry-run   Print what would happen without changing anything"
        echo "  -h, --help      Show this message"
        DOTFILES_SUPPRESS_STEPS=1
        exit 0
        ;;
      *)
        echo "Unknown option: $1" >&2
        echo "Try: ${ZSH_SCRIPT:t} --help" >&2
        DOTFILES_SUPPRESS_STEPS=1
        exit 1
        ;;
    esac
    shift
  done
}

# ── Config installation ───────────────────────────────────────────────────────
install_config() {
  local source_file="$1"
  local target_file="$2"
  local mode="${3:-0644}"

  # A missing asset is a bug in this repo, but it must not abort a run that is
  # otherwise fine — the rest of the module still has useful work to do.
  if [ ! -f "$source_file" ]; then
    warn "Missing config asset: $source_file"
    return 0
  fi

  if dry_run; then
    info "[dry run] install ${source_file:t} -> $target_file (mode $mode)"
    return 0
  fi

  if [ -e "$target_file" ] || [ -L "$target_file" ]; then
    local relative_path="${target_file#$HOME/}"
    local backup_file="$DOTFILES_BACKUP_DIR/$relative_path"
    mkdir -p "${backup_file:h}"
    # -L dereferences, so the backup holds real content rather than a link.
    cp -pL "$target_file" "$backup_file"
    # Replace a symlink rather than writing through it to its target.
    if [ -L "$target_file" ]; then
      rm "$target_file"
    fi
  fi

  mkdir -p "${target_file:h}"
  cp "$source_file" "$target_file"
  chmod "$mode" "$target_file"
}

# ── Homebrew ──────────────────────────────────────────────────────────────────
ensure_homebrew() {
  if command -v brew &>/dev/null; then
    return 0
  fi

  # Apple Silicon first, then Intel.
  local prefix
  for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
      eval "$("$prefix/bin/brew" shellenv)"
      return 0
    fi
  done

  if dry_run; then
    info "[dry run] install Homebrew"
    return 0
  fi

  info "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
      eval "$("$prefix/bin/brew" shellenv)"
      return 0
    fi
  done

  warn "Homebrew was installed but could not be found on PATH."
  return 1
}

brew_install_formulae() {
  local formula
  for formula in "$@"; do
    if dry_run; then
      info "[dry run] brew install $formula"
      continue
    fi
    if brew list --formula "$formula" &>/dev/null; then
      success "$formula already installed."
    else
      info "Installing $formula..."
      brew install "$formula"
    fi
  done
}

brew_install_casks() {
  local cask
  for cask in "$@"; do
    if dry_run; then
      info "[dry run] brew install --cask $cask"
      continue
    fi
    if brew list --cask "$cask" &>/dev/null; then
      success "$cask already installed."
    else
      info "Installing $cask..."
      brew install --cask "$cask"
    fi
  done
}
