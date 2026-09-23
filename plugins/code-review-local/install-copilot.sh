#!/usr/bin/env bash
# Installs this plugin's Copilot bundle (prompt file + instructions snippet)
# into a target repo's .github/ folder. GitHub Copilot has no portable
# plugin-installer, so this is the closest equivalent: copy files into the
# repo that wants them. Safe to re-run (idempotent).
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

mkdir -p "$TARGET_REPO/.github/prompts"
cp "$SCRIPT_DIR/copilot/prompts/code-review-local.prompt.md" "$TARGET_REPO/.github/prompts/code-review-local.prompt.md"
echo "Copied code-review-local.prompt.md -> $TARGET_REPO/.github/prompts/"

SNIPPET="$SCRIPT_DIR/copilot/copilot-instructions.snippet.md"
INSTRUCTIONS="$TARGET_REPO/.github/copilot-instructions.md"
MARKER="## Local code review (code-review-local)"

if [[ -f "$INSTRUCTIONS" ]] && grep -qF "$MARKER" "$INSTRUCTIONS"; then
  echo "copilot-instructions.md already has the code-review-local section, leaving it as-is."
else
  touch "$INSTRUCTIONS"
  {
    echo ""
    cat "$SNIPPET"
  } >> "$INSTRUCTIONS"
  echo "Appended code-review-local section -> $INSTRUCTIONS"
fi

echo "Done. In Copilot Chat, run /code-review-local (or reference the prompt file directly)."
