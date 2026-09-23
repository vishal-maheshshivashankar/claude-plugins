# code-review-local

Local-only code review, mirroring the review process robin (this author's internal Slack bot)
runs via its `code-review-dev` skill — same `code-reviewer` agent, same parallel three-focus
review (simplicity/DRY, bugs/correctness, project conventions), same confidence-based filtering
(only ≥80/100 confidence issues get reported).

**The one hard rule this plugin adds:** it never writes back anywhere. No GitLab MR comment, no
MR approval, no GitHub PR review — the chat message is the entire deliverable, always.

It also accepts a **pasted MR/PR description** as input, not just a URL/ID, and supports **GitHub
PRs** (via `gh`) in addition to **GitLab MRs** (via `glab`).

## Install — Claude Code

From any project:

```
/plugin marketplace add vishal-maheshshivashankar/claude-plugins
/plugin install code-review-local
```

Then, in any repo:

```
/code-review-local https://gitlab.example.com/group/project/-/merge_requests/123
/code-review-local https://github.com/owner/repo/pull/45
/code-review-local <paste the MR/PR title + description here>
/code-review-local                      # no argument: reviews local branch vs. a branch you confirm
```

## Install — GitHub Copilot

Copilot has no plugin installer, so this copies files into the target repo instead:

```bash
./install-copilot.sh /path/to/some/other/repo
```

This drops `code-review-local.prompt.md` into that repo's `.github/prompts/` and appends a short
"never post back" instruction to its `.github/copilot-instructions.md` (creating it if needed,
skipping the append if it's already there). Then, in VS Code Copilot Chat, in that repo:

```
/code-review-local <MR/PR URL, pasted description, or nothing>
```

## Requirements

- `git`, `jq` always.
- `glab` (authenticated) for GitLab MR mode.
- `gh` (authenticated) for GitHub PR mode.
- Neither `glab` nor `gh` is required for the pasted-description or no-MR local-diff paths.

## Files

```
.claude-plugin/plugin.json          Claude Code plugin manifest
agents/code-reviewer.md             The reviewer agent (confidence-scored findings)
skills/code-review-local/SKILL.md   The orchestrating skill (Claude Code)
skills/code-review-local/scripts/   git/GitLab/GitHub plumbing (clone/review/summary)
copilot/prompts/*.prompt.md         The Copilot Chat equivalent
copilot/copilot-instructions.snippet.md   Appended into a target repo's copilot-instructions.md
install-copilot.sh                  Copies the two files above into a target repo
```
