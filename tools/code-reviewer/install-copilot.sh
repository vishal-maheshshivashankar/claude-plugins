#!/usr/bin/env bash
# Installs this plugin's Copilot bundle (prompt file + instructions snippet).
# GitHub Copilot has no portable plugin-installer, so this is the closest
# equivalent. Two modes:
#
#   install-copilot.sh <path-to-target-repo>   Per-repo install (reliable today,
#                                               works in standard VS Code Copilot
#                                               Chat). Copies into that repo's
#                                               .github/ — must be re-run per repo.
#
#   install-copilot.sh --global                EXPERIMENTAL. Copies into
#                                               ~/.copilot/prompts/, which VS Code's
#                                               docs describe as a user-level
#                                               location read by "Agent Host"
#                                               sessions — not confirmed to work in
#                                               standard VS Code Copilot Chat. Try
#                                               it, but don't rely on it until
#                                               you've verified Copilot Chat in your
#                                               setup actually picks it up.
#
# Safe to re-run either mode (idempotent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-}"

install_prompt_and_snippet() {
  local prompts_dir="$1" instructions_file="$2"

  mkdir -p "$prompts_dir"
  cp "$SCRIPT_DIR/copilot/prompts/code-review.prompt.md" "$prompts_dir/code-review.prompt.md"
  echo "Copied code-review.prompt.md -> $prompts_dir/"

  local snippet="$SCRIPT_DIR/copilot/copilot-instructions.snippet.md"
  local marker="## Local code review (code-review)"

  if [[ -f "$instructions_file" ]] && grep -qF "$marker" "$instructions_file"; then
    echo "$(basename "$instructions_file") already has the code-review section, leaving it as-is."
  else
    mkdir -p "$(dirname "$instructions_file")"
    touch "$instructions_file"
    {
      echo ""
      cat "$snippet"
    } >> "$instructions_file"
    echo "Appended code-review section -> $instructions_file"
  fi
}

if [[ "$MODE" == "--global" ]]; then
  echo "EXPERIMENTAL: installing to ~/.copilot/ (Agent Host user-level location, not"
  echo "confirmed to work in standard VS Code Copilot Chat — verify it's picked up)."
  install_prompt_and_snippet "$HOME/.copilot/prompts" "$HOME/.copilot/copilot-instructions.md"
  echo "Done. Try /code-review in Copilot Chat from any project; if it's not found,"
  echo "fall back to the per-repo install: install-copilot.sh <path-to-target-repo>"
  exit 0
fi

TARGET_REPO="$MODE"

if [[ -z "$TARGET_REPO" ]]; then
  echo "Usage: install-copilot.sh <path-to-target-repo>" >&2
  echo "       install-copilot.sh --global   (experimental, see script header)" >&2
  exit 1
fi

if [[ ! -d "$TARGET_REPO/.git" ]]; then
  echo "Error: $TARGET_REPO doesn't look like a git repo (no .git dir)." >&2
  exit 1
fi

install_prompt_and_snippet "$TARGET_REPO/.github/prompts" "$TARGET_REPO/.github/copilot-instructions.md"
echo "Done. In Copilot Chat, run /code-review (or reference the prompt file directly)."
