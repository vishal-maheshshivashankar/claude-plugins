# code-reviewer

Local-only code review, mirroring the review process robin (this author's internal Slack bot)
runs via its `code-review-dev` skill — same `code-reviewer` agent, same parallel three-focus
review (simplicity/DRY, bugs/correctness, project conventions), same confidence-based filtering
(only ≥80/100 confidence issues get reported).

**The one hard rule this adds:** it never writes back anywhere. No GitLab MR comment, no MR
approval, no GitHub PR review — the chat message is the entire deliverable, always.

It also accepts a **pasted MR/PR description** as input, not just a URL/ID, and supports **GitHub
PRs** (via `gh`) in addition to **GitLab MRs** (via `glab`).

This ships as a **standalone Claude Code skill**, not a plugin — that's a deliberate choice: a
plugin-shipped skill is always invoked as `/plugin-name:skill-name` (Claude Code's own
collision-prevention rule, no way around it), whereas a standalone skill placed in
`~/.claude/skills/` gets a bare command name and is still available in every project on the
machine. This trades away `/plugin install`/marketplace mechanics for the shorter `/code-reviewer`
command.

---

## Install & use — Claude Code

### 1. Prerequisites

- Claude Code (any recent version).
- `git` and `jq` on `PATH` — always required.
- `glab` (authenticated: `glab auth status`) — only needed to review a **GitLab MR**.
- `gh` (authenticated: `gh auth status`) — only needed to review a **GitHub PR**.
- Neither `glab` nor `gh` is required if you're reviewing a pasted description or a local branch
  diff — those two only matter for the URL/ID input mode.

### 2. Install (one time, per machine)

```bash
git clone https://github.com/vishal-maheshshivashankar/claude-plugins.git
./claude-plugins/tools/code-reviewer/install-claude.sh
```

This symlinks `skills/code-reviewer/` into `~/.claude/skills/code-reviewer` and
`agents/code-reviewer.md` into `~/.claude/agents/code-reviewer.md`. Because they're symlinks (not
copies), a later `git pull` in `claude-plugins/` updates what's installed automatically — no
re-install step needed after this repo changes. If you'd rather have real copies (e.g. your setup
doesn't like symlinks under `~/.claude`), run `install-claude.sh --copy` instead; you'll need to
re-run it after every update in that case.

This is a **machine-wide** install: once run, the skill is available in *every* project you open
in Claude Code afterwards — you don't repeat this per project.

### 3. Verify it installed

```bash
ls -la ~/.claude/skills/code-reviewer ~/.claude/agents/code-reviewer.md
```

Both should show up (as symlinks, unless you used `--copy`). Then, in a fresh Claude Code session
in any project, type `/` and confirm `code-reviewer` appears in the command list. If it doesn't
show up right away, restart Claude Code, or try `/reload-plugins`.

### 4. Use it

In any repo, any project, any time after install:

```
/code-reviewer https://gitlab.example.com/group/project/-/merge_requests/123
```
Reviews a GitLab MR — fetches title, description, comments, and linked issues via `glab`, then
diffs the MR branch against its target.

```
/code-reviewer https://github.com/owner/repo/pull/45
```
Same, but for a GitHub PR via `gh`.

```
/code-reviewer <paste the MR/PR title + description here>
```
No URL needed — paste the actual description text (from a GitLab/GitHub UI, a Slack message,
wherever). The skill uses your local checkout's current branch as the change being reviewed and
asks you (once) which branch to diff against.

```
/code-reviewer
```
No argument at all — reviews your local branch's changes. It'll ask which branch to diff against
and, since there's no description to go on, propose one inferred from your commit messages for
you to confirm or correct.

In every case, the output is a `### Code review` message in that same chat — a numbered list of
issues (or "No issues found") with file/line references. Nothing is posted anywhere; if you want
the review posted to the real MR/PR afterwards, do that yourself via `glab mr note` / `gh pr
review`, or ask Claude to do it as a separate, explicit step outside this skill.

### Updating

```bash
git -C claude-plugins pull
```
That's it if you installed with symlinks (the default). If you used `--copy`, re-run
`install-claude.sh --copy` after pulling.

### Uninstalling

```bash
rm ~/.claude/skills/code-reviewer ~/.claude/agents/code-reviewer.md
```
(`rm -r` instead of `rm` if you installed with `--copy`, since those are real directories/files
rather than symlinks.)

---

## Install & use — GitHub Copilot

Copilot has no plugin installer and no confirmed machine-wide install path in standard VS Code
Copilot Chat today (see the experimental option at the end), so this is a **per-repo file copy**
— unrelated to the Claude Code install above, and unaffected by the standalone-vs-plugin choice.

### 1. Prerequisites

- VS Code with GitHub Copilot Chat.
- `git` and `jq` on `PATH`.
- `glab` or `gh`, same as above, only if you'll use the URL input mode.
- The Copilot agent needs terminal/shell execution enabled in your VS Code setup (see the note
  inside the prompt file itself — the exact tool name for this varies by Copilot version, so it's
  intentionally not hardcoded).

### 2. Install into a target repo (repeat per repo)

```bash
./claude-plugins/tools/code-reviewer/install-copilot.sh /path/to/some/other/repo
```

This copies `code-review.prompt.md` into that repo's `.github/prompts/` and appends a short
"never post back" instruction to its `.github/copilot-instructions.md` (creating the file if it
doesn't exist, and skipping the append if it's already there — safe to re-run any time you want
to re-sync after this repo changes).

You have to run this once per repo you want it in — there's no single install that reaches every
project the way the Claude Code skill above does.

### 3. Verify it installed

```bash
ls /path/to/some/other/repo/.github/prompts/code-review.prompt.md
```

Then, in VS Code Copilot Chat opened on that repo, type `/` — `code-review` should appear in the
autocomplete list of available prompts.

### 4. Use it

In Copilot Chat, in that repo:

```
/code-review https://gitlab.example.com/group/project/-/merge_requests/123
/code-review https://github.com/owner/repo/pull/45
/code-review <paste the MR/PR title + description here>
/code-review
```

Same four input modes as the Claude Code version, same confidence-based filtering, same "report
in chat, never post back" rule — this is a single Copilot agent doing three sequential review
passes (simplicity, bugs, conventions) rather than three parallel subagents, since Copilot Chat
doesn't support the latter.

### Updating

```bash
git -C claude-plugins pull
./claude-plugins/tools/code-reviewer/install-copilot.sh /path/to/some/other/repo
```

### Uninstalling

Delete the file it added:

```bash
rm /path/to/some/other/repo/.github/prompts/code-review.prompt.md
```

...and manually remove the `## Local code review (code-review)` section from that repo's
`.github/copilot-instructions.md`.

### Experimental: one global install instead of per-repo

```bash
./claude-plugins/tools/code-reviewer/install-copilot.sh --global
```

This copies the same two files into `~/.copilot/` instead of a specific repo's `.github/`. VS
Code's own docs describe `~/.copilot/` as a user-level location read by a newer "Agent Host"
session type — if your Copilot setup uses that, this could give you the same "install once, use
in every repo" behavior the Claude Code skill above has. **This is not confirmed to work in
standard VS Code Copilot Chat.** After running it, open Copilot Chat in some other repo and check
whether `/code-review` shows up; if it doesn't, fall back to the per-repo install above.

---

## Requirements summary

- `git`, `jq` always.
- `glab` (authenticated) for GitLab MR mode.
- `gh` (authenticated) for GitHub PR mode.
- Neither `glab` nor `gh` is required for the pasted-description or no-MR local-diff paths.

## Files

```
agents/code-reviewer.md                    The reviewer agent (confidence-scored findings)
skills/code-reviewer/SKILL.md              The orchestrating skill (Claude Code) — /code-reviewer
skills/code-reviewer/scripts/              git/GitLab/GitHub plumbing (clone/review/summary)
copilot/prompts/code-review.prompt.md      The Copilot Chat equivalent — /code-review
copilot/copilot-instructions.snippet.md    Appended into a target repo's copilot-instructions.md
install-claude.sh                          Symlinks skill+agent into ~/.claude/ (Claude Code)
install-copilot.sh                         Copies prompt+snippet into a target repo (or --global)
```
