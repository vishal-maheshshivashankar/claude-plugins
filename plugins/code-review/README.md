# code-review

Local-only code review, mirroring the review process robin (this author's internal Slack bot)
runs via its `code-review-dev` skill — same `code-reviewer` agent, same parallel three-focus
review (simplicity/DRY, bugs/correctness, project conventions), same confidence-based filtering
(only ≥80/100 confidence issues get reported).

**The one hard rule this plugin adds:** it never writes back anywhere. No GitLab MR comment, no
MR approval, no GitHub PR review — the chat message is the entire deliverable, always.

It also accepts a **pasted MR/PR description** as input, not just a URL/ID, and supports **GitHub
PRs** (via `gh`) in addition to **GitLab MRs** (via `glab`).

---

## Install & use — Claude Code

### 1. Prerequisites

- Claude Code (any recent version with plugin support).
- `git` and `jq` on `PATH` — always required.
- `glab` (authenticated: `glab auth status`) — only needed to review a **GitLab MR**.
- `gh` (authenticated: `gh auth status`) — only needed to review a **GitHub PR**.
- Neither `glab` nor `gh` is required if you're reviewing a pasted description or a local branch
  diff — those two only matter for the URL/ID input mode.

### 2. Add the marketplace (one time, ever)

```
/plugin marketplace add vishal-maheshshivashankar/claude-plugins
```

This registers the marketplace repo with your Claude Code install. It doesn't install anything
by itself — it just makes the plugins in it visible to `/plugin install`.

### 3. Install the plugin (one time, per machine)

```
/plugin install code-review
```

This is a **machine-wide** install, not a per-project one: once installed, the plugin is
available in *every* project you open in Claude Code afterwards, without repeating this step.
That's the whole difference between a plugin and a plain `.claude/` folder — the latter is
per-project, the former isn't.

If Claude Code reports `Run /reload-plugins to activate.`, run:

```
/reload-plugins
```

### 4. Verify it installed

```
/help
```

Open the **Custom commands** tab and confirm `code-review:local` is listed under the
`code-review` plugin namespace. (Claude Code always namespaces plugin skills as
`/plugin-name:skill-name` to prevent two plugins from colliding on the same command name — that's
why the command isn't a bare `/code-review`.)

### 5. Use it

In any repo, any project, any time after install:

```
/code-review:local https://gitlab.example.com/group/project/-/merge_requests/123
```
Reviews a GitLab MR — fetches title, description, comments, and linked issues via `glab`, then
diffs the MR branch against its target.

```
/code-review:local https://github.com/owner/repo/pull/45
```
Same, but for a GitHub PR via `gh`.

```
/code-review:local <paste the MR/PR title + description here>
```
No URL needed — paste the actual description text (from a GitLab/GitHub UI, a Slack message,
wherever). The skill uses your local checkout's current branch as the change being reviewed and
asks you (once) which branch to diff against.

```
/code-review:local
```
No argument at all — reviews your local branch's changes. It'll ask you which branch to diff
against and, since there's no description to go on, propose one inferred from your commit
messages for you to confirm or correct.

In every case, the output is a `### Code review` message in that same chat — a numbered list of
issues (or "No issues found") with file/line references. Nothing is posted anywhere; if you want
the review posted to the real MR/PR afterwards, do that yourself via `glab mr note` / `gh pr
review`, or ask Claude to do it as a separate, explicit step outside this skill.

### Updating

After this repo gets new commits:

```
/plugin marketplace update vishalm-claude-plugins
```

### Uninstalling

```
/plugin uninstall code-review
```

---

## Install & use — GitHub Copilot

Copilot has no plugin installer and no confirmed machine-wide install path in standard VS Code
Copilot Chat today (see the experimental option at the end), so this is a **per-repo file copy**.

### 1. Prerequisites

- VS Code with GitHub Copilot Chat.
- `git` and `jq` on `PATH`.
- `glab` or `gh`, same as above, only if you'll use the URL input mode.
- The Copilot agent needs terminal/shell execution enabled in your VS Code setup (see the note
  inside the prompt file itself — the exact tool name for this varies by Copilot version, so it's
  intentionally not hardcoded).

### 2. Install into a target repo (repeat per repo)

```bash
git clone https://github.com/vishal-maheshshivashankar/claude-plugins.git
./claude-plugins/plugins/code-review/install-copilot.sh /path/to/some/other/repo
```

This copies `code-review.prompt.md` into that repo's `.github/prompts/` and appends a short
"never post back" instruction to its `.github/copilot-instructions.md` (creating the file if it
doesn't exist, and skipping the append if it's already there — safe to re-run any time you want
to re-sync after this repo changes).

You have to run this once per repo you want it in — there's no single install that reaches every
project the way the Claude Code plugin does.

### 3. Verify it installed

Check that the file landed:

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
./claude-plugins/plugins/code-review/install-copilot.sh /path/to/some/other/repo
```

### Uninstalling

Delete the two files it added:

```bash
rm /path/to/some/other/repo/.github/prompts/code-review.prompt.md
```

...and manually remove the `## Local code review (code-review)` section from that repo's
`.github/copilot-instructions.md`.

### Experimental: one global install instead of per-repo

```bash
./claude-plugins/plugins/code-review/install-copilot.sh --global
```

This copies the same two files into `~/.copilot/` instead of a specific repo's `.github/`. VS
Code's own docs describe `~/.copilot/` as a user-level location read by a newer "Agent Host"
session type — if your Copilot setup uses that, this could give you the same "install once, use
in every repo" behavior the Claude Code plugin has. **This is not confirmed to work in standard
VS Code Copilot Chat.** After running it, open Copilot Chat in some other repo and check whether
`/code-review` shows up; if it doesn't, fall back to the per-repo install above.

---

## Requirements summary

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
