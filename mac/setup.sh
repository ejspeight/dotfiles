#!/usr/bin/env zsh
# ==============================================================================
#  Mac Dev Environment Setup
#
#  Picks and runs the modules you want. Each module under modules/ also runs on
#  its own, so "just give me a terminal" is one script, not a flag you have to
#  remember.
#
#    ./setup.sh                    choose from a menu
#    ./setup.sh --terminal         one module
#    ./setup.sh --terminal --dev   several
#    ./setup.sh --all --dry-run    see what would happen, change nothing
# ==============================================================================

set -e
source "${${(%):-%x}:A:h}/lib.sh"

MODULE_ORDER=(terminal dev llm)

typeset -A MODULE_SUMMARY=(
  terminal "Ghostty, zsh, Starship, Atuin, and the shell tools"
  dev      "Node, Go, Python, Rust, Neovim, Docker, databases, AWS CLI"
  llm      "Ollama and a local terminal model"
)

usage() {
  cat <<USAGE
Usage: ./setup.sh [modules] [options]

Modules:
  --terminal   ${MODULE_SUMMARY[terminal]}
  --dev        ${MODULE_SUMMARY[dev]}
  --llm        ${MODULE_SUMMARY[llm]}
  --all        Everything above

Options:
  --dry-run    Print what would happen without changing anything
  -h, --help   Show this message

With no modules given, you are asked which ones you want.
Each module is also runnable on its own, for example:  ./modules/terminal.sh
USAGE
}

# ── Arguments ─────────────────────────────────────────────────────────────────
typeset -a requested

while (( $# )); do
  case "$1" in
    --terminal|--dev|--llm) requested+=("${1#--}") ;;
    --all)      requested=("${MODULE_ORDER[@]}") ;;
    --dry-run)  export DOTFILES_DRY_RUN=1 ;;
    -h|--help)  usage; DOTFILES_SUPPRESS_STEPS=1; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      echo "" >&2
      usage >&2
      DOTFILES_SUPPRESS_STEPS=1
      exit 1
      ;;
  esac
  shift
done

# ── Menu ──────────────────────────────────────────────────────────────────────
if (( ${#requested} == 0 )); then
  echo ""
  echo "${BOLD}Mac Dev Environment Setup${RESET}"
  echo ""
  echo "Which modules do you want?"
  local index=1
  for module in "${MODULE_ORDER[@]}"; do
    printf '  %d) %-9s %s\n' "$index" "$module" "${MODULE_SUMMARY[$module]}"
    (( index++ ))
  done
  echo "  a) all of them"
  echo ""

  read "reply?Choose (e.g. 1 2, or a): "
  echo ""

  # Accept "1 2", "1,2", "12", "terminal dev", "a" or "all".
  for choice in ${(s: :)${reply//,/ }}; do
    case "$choice" in
      a|all)                         requested=("${MODULE_ORDER[@]}") ;;
      terminal|dev|llm)              requested+=("$choice") ;;
      *)
        # One or more digits, together or apart: "2", "1 3", "13".
        if [[ "$choice" == <-> ]]; then
          for digit in ${(s::)choice}; do
            if (( digit >= 1 && digit <= ${#MODULE_ORDER} )); then
              requested+=("${MODULE_ORDER[$digit]}")
            else
              warn "There is no module $digit."
            fi
          done
        else
          warn "Ignoring unrecognised choice: $choice"
        fi
        ;;
    esac
  done
fi

# ── Run ───────────────────────────────────────────────────────────────────────
# Always in dependency order, and never twice, whatever order they were asked
# for: the terminal config should land before anything that reports on it.
typeset -a selected
for module in "${MODULE_ORDER[@]}"; do
  if (( ${requested[(Ie)$module]} )); then
    selected+=("$module")
  fi
done

if (( ${#selected} == 0 )); then
  warn "No modules selected, nothing to do."
  DOTFILES_SUPPRESS_STEPS=1
  exit 0
fi

echo ""
echo "${BOLD}Running:${RESET} ${selected[*]}"
dry_run && warn "Dry run — nothing will be installed or written."
echo ""

for module in "${selected[@]}"; do
  zsh "$MODULES_DIR/$module.sh"
  echo ""
done

echo "${GREEN}${BOLD}All selected modules are done.${RESET}"
