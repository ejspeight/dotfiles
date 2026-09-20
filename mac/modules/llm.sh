#!/usr/bin/env zsh
# ==============================================================================
#  Module: llm
#
#  A local model for the terminal: Ollama to run it, the llm CLI to talk to it,
#  and a terminal-llm model built with a 16K context and thinking turned off.
#  Everything runs on this machine; no account and no cloud service.
#
#  The model is sized to installed RAM. Override with:
#    LOCAL_LLM_MODEL=<ollama tag> ./modules/llm.sh
#
#  Run on its own:  ./modules/llm.sh
# ==============================================================================

set -e
source "${${(%):-%x}:A:h}/../lib.sh"

MODULE_DESCRIPTION="Ollama and a local terminal model driven by the llm CLI."
module_args "$@"

FORMULAE=(
  ollama
  llm
)

info "Setting up the local LLM..."
ensure_homebrew
brew_install_formulae "${FORMULAE[@]}"

readonly LLM_MODEL="terminal-llm"

# Pick a model that fits this Mac's unified memory. macOS lets the GPU use
# roughly two-thirds of RAM, so the model plus its context must fit in that.
RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
if [ -n "$LOCAL_LLM_MODEL" ]; then
  LLM_BASE_MODEL="$LOCAL_LLM_MODEL"
elif [ "$RAM_GB" -ge 32 ]; then
  LLM_BASE_MODEL="gemma4:26b"   # ~16GB
elif [ "$RAM_GB" -ge 16 ]; then
  LLM_BASE_MODEL="gemma4:12b"   # ~8GB
else
  LLM_BASE_MODEL="gemma4:e4b"   # small model for 8GB Macs
fi
info "Detected ${RAM_GB}GB RAM, using $LLM_BASE_MODEL."

if dry_run; then
  info "[dry run] start ollama, install the llm plugins and build $LLM_MODEL from $LLM_BASE_MODEL"
  next_step "Test the local LLM: llm \"Say hi in five words\""
  success "LLM module done."
  return 0 2>/dev/null || exit 0
fi

brew services start ollama >/dev/null 2>&1 || warn "Could not start the Ollama service."

# A plugin install failure must not abort the run; the warning says what broke.
if llm install llm-ollama llm-cmd; then
  llm logs off
  success "llm CLI ready, conversation logging off."
else
  warn "Could not install the llm plugins (llm-ollama, llm-cmd)."
fi

# Wait for the Ollama service to accept requests.
for _ in {1..15}; do
  ollama list &>/dev/null && break
  sleep 1
done

# Download the model, add a 16K context window, make it the llm default and
# turn thinking off for quick terminal answers.
LLM_MODELFILE="$(mktemp)"
sed "s|__BASE_MODEL__|$LLM_BASE_MODEL|" "$CONFIG_DIR/ollama/Modelfile" > "$LLM_MODELFILE"

if ollama pull "$LLM_BASE_MODEL" \
  && ollama create "$LLM_MODEL" -f "$LLM_MODELFILE" \
  && llm models default "$LLM_MODEL" \
  && llm models options set "$LLM_MODEL" think false; then
  success "Local LLM ready: $LLM_MODEL ($LLM_BASE_MODEL, 16K context, thinking off)."
else
  warn "Local model setup did not finish. See the Local LLM section of the README."
fi
rm -f "$LLM_MODELFILE"

next_step "Test the local LLM: llm \"Say hi in five words\""

success "LLM module done."
