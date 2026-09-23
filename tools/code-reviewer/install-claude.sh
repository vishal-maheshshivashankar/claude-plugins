#!/usr/bin/env bash
# Installs the code-reviewer skill + agent as a standalone (non-plugin)
# global Claude Code skill, available in every project on this machine as a
# bare /code-reviewer command. Symlinks by default so a later `git pull` in
# this repo updates the installed copy automatically; pass --copy to copy
# the files instead (e.g. if your setup doesn't like symlinks in ~/.claude).
#
# Usage: install-claude.sh [--copy]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="${1:-}"

SKILL_SRC="$SCRIPT_DIR/skills/code-reviewer"
AGENT_SRC="$SCRIPT_DIR/agents/code-reviewer.md"
SKILL_DEST="$HOME/.claude/skills/code-reviewer"
AGENT_DEST="$HOME/.claude/agents/code-reviewer.md"

mkdir -p "$HOME/.claude/skills" "$HOME/.claude/agents"

link_or_copy() {
  local src="$1" dest="$2"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
      echo "Already linked: $dest -> $src"
      return
    fi
    echo "Removing existing $dest before re-installing"
    rm -rf "$dest"
  fi

  if [[ "$MODE" == "--copy" ]]; then
    cp -r "$src" "$dest"
    echo "Copied $src -> $dest"
  else
    ln -s "$src" "$dest"
    echo "Linked $src -> $dest"
  fi
}

link_or_copy "$SKILL_SRC" "$SKILL_DEST"
link_or_copy "$AGENT_SRC" "$AGENT_DEST"

echo ""
echo "Done. Restart Claude Code (or run /reload-plugins if that's not enough) and"
echo "try /code-reviewer in any project."
