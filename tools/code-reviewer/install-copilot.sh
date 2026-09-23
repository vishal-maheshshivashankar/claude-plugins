#!/usr/bin/env bash
# Installs this tool's Copilot bundle (prompt file + instructions snippet)
# into a target repo's .github/ folder. GitHub Copilot has no portable
# plugin-installer and no confirmed machine-wide install location — a
# ~/.copilot/ global install was tried and confirmed NOT picked up by
# standard VS Code Copilot Chat (tested 2026-09-23), so this is per-repo
# only. Safe to re-run (idempotent).
#
# Usage: install-copilot.sh <path-to-target-repo>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_REPO="${1:-}"

if [[ -z "$TARGET_REPO" ]]; then
  echo "Usage: install-copilot.sh <path-to-target-repo>" >&2
  exit 1
fi

if [[ ! -d "$TARGET_REPO/.git" ]]; then
  echo "Error: $TARGET_REPO doesn't look like a git repo (no .git dir)." >&2
  exit 1
fi

PROMPTS_DIR="$TARGET_REPO/.github/prompts"
INSTRUCTIONS_FILE="$TARGET_REPO/.github/copilot-instructions.md"

mkdir -p "$PROMPTS_DIR"
cp "$SCRIPT_DIR/copilot/prompts/code-review.prompt.md" "$PROMPTS_DIR/code-review.prompt.md"
echo "Copied code-review.prompt.md -> $PROMPTS_DIR/"

SNIPPET="$SCRIPT_DIR/copilot/copilot-instructions.snippet.md"
MARKER="## Local code review (code-review)"

if [[ -f "$INSTRUCTIONS_FILE" ]] && grep -qF "$MARKER" "$INSTRUCTIONS_FILE"; then
  echo "$(basename "$INSTRUCTIONS_FILE") already has the code-review section, leaving it as-is."
else
  touch "$INSTRUCTIONS_FILE"
  {
    echo ""
    cat "$SNIPPET"
  } >> "$INSTRUCTIONS_FILE"
  echo "Appended code-review section -> $INSTRUCTIONS_FILE"
fi

echo "Done. In Copilot Chat, run /code-review (or reference the prompt file directly)."
