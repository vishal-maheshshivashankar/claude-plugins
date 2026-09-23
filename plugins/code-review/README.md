# code-review

Local-only code review, mirroring the review process robin (this author's internal Slack bot)
runs via its `code-review-dev` skill — same `code-reviewer` agent, same parallel three-focus
review (simplicity/DRY, bugs/correctness, project conventions), same confidence-based filtering
(only ≥80/100 confidence issues get reported).

**The one hard rule this plugin adds:** it never writes back anywhere. No GitLab MR comment, no
MR approval, no GitHub PR review — the chat message is the entire deliverable, always.

It also accepts a **pasted MR/PR description** as input, not just a URL/ID, and supports **GitHub
PRs** (via `gh`) in addition to **GitLab MRs** (via `glab`).

## Install — Claude Code

From any project, once:

```
/plugin marketplace add vishal-maheshshivashankar/claude-plugins
/plugin install code-review
```

That's a one-time, machine-wide install — Claude Code plugins are available in every project you
open afterwards, not just the one you were in when you ran `/plugin install`. No per-project
download needed. (Note: plugin skills are always namespaced as `/plugin-name:skill-name` — this
is a Claude Code design choice to prevent name collisions between plugins, so the command is
`/code-review:local`, not a bare `/code-review`.)

In any repo:

```
/code-review:local https://gitlab.example.com/group/project/-/merge_requests/123
/code-review:local https://github.com/owner/repo/pull/45
/code-review:local <paste the MR/PR title + description here>
/code-review:local                      # no argument: reviews local branch vs. a branch you confirm
```

## Install — GitHub Copilot

Copilot has no plugin installer and no confirmed machine-wide install path in standard VS Code
Copilot Chat today, so this is a per-repo copy:

```bash
./install-copilot.sh /path/to/some/other/repo
```

This drops `code-review.prompt.md` into that repo's `.github/prompts/` and appends a short
"never post back" instruction to its `.github/copilot-instructions.md` (creating it if needed,
skipping the append if it's already there). Then, in VS Code Copilot Chat, in that repo:

```
/code-review <MR/PR URL, pasted description, or nothing>
```

You have to re-run this once per repo you want it in — there's no single install that reaches
every project the way the Claude Code plugin does.

**Experimental, not per-repo:** `./install-copilot.sh --global` copies the same bundle into
`~/.copilot/`, which VS Code's docs describe as a user-level location read by a newer "Agent
Host" session type — potentially machine-wide, like the Claude Code plugin. This is **not
confirmed to work in standard VS Code Copilot Chat**; try it and verify `/code-review` is
actually picked up before relying on it, and fall back to the per-repo install if not.

## Requirements

- `git`, `jq` always.
- `glab` (authenticated) for GitLab MR mode.
- `gh` (authenticated) for GitHub PR mode.
- Neither `glab` nor `gh` is required for the pasted-description or no-MR local-diff paths.

## Files

```
.claude-plugin/plugin.json          Claude Code plugin manifest
agents/code-reviewer.md             The reviewer agent (confidence-scored findings)
skills/local/SKILL.md               The orchestrating skill (Claude Code) — /code-review:local
skills/local/scripts/               git/GitLab/GitHub plumbing (clone/review/summary)
copilot/prompts/code-review.prompt.md     The Copilot Chat equivalent — /code-review
copilot/copilot-instructions.snippet.md   Appended into a target repo's copilot-instructions.md
install-copilot.sh                  Copies the two files above into a target repo (or --global)
```
