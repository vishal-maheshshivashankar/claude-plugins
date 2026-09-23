---
name: code-review-local
description: Review a GitLab MR, a GitHub PR (by URL or ID), a pasted MR/PR description, or — when none of those is available — the current local branch's changes against a target branch you confirm with the user first. Runs entirely in this local session and only ever reports findings in this chat — it never posts a comment, note, review, or approval back to the MR/PR. Mirrors robin's code-review-dev process (same parallel code-reviewer agents, same confidence-based filtering, same findings format) with the remote-posting step removed entirely. Use when the user pastes an MR/PR URL, or the full MR/PR description text, and wants a local-only review report.
argument-hint: <MR-URL|PR-URL|MR-ID> | <pasted MR/PR description> | (no argument = review local branch changes)
tools: Read, Bash, Grep, Glob, Agent, AskUserQuestion, Write
---

# Local Code Review

Review the merge request, pull request, pasted description, or local branch changes: $ARGUMENTS

This mirrors robin's `code-review-dev` skill (itself a local mirror of the sandboxed
`git-mr-review` skill `code_engineer` runs) — same steps, same `code-reviewer` agent, same
findings format. Differences, all deliberate:

- **Never posts anywhere.** No GitLab comment, no MR approval, no GitHub PR review — not even
  on confirmation. The chat message in Step 3 is the entire deliverable, every time. The only
  optional follow-up is saving the report to a local file, if the user asks.
- **Accepts a pasted description as a first-class input**, not just a URL/ID. If the user pastes
  the MR/PR's title/description text instead of (or alongside) a link, use that text directly as
  the review context — don't call `glab`/`gh` to re-fetch it.
- **Supports GitHub PRs as well as GitLab MRs.** A full `github.com/.../pull/<n>` URL uses `gh`;
  a GitLab MR URL or bare numeric ID uses `glab` (matching robin's original environment).
- Runs directly against your local checkout — no sandbox, no `claude()`/`bash()` HTTP hop.

Depends on this plugin's own `agents/code-reviewer.md` (same agent robin uses) to actually
perform the review in Step 2, and on `scripts/git-utils.sh` in this skill's own directory for the
`clone` / `review` / `summary` git+forge plumbing. Always invoke the script via
`"${CLAUDE_PLUGIN_ROOT}"` so the path resolves correctly regardless of where the plugin was
installed from:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/code-review-local/scripts/git-utils.sh <command> [args...]
```

Prerequisites: `git`, `jq` on PATH (always). `glab` (authenticated) for GitLab MR mode; `gh`
(authenticated) for GitHub PR mode. Neither is needed for the pasted-description or no-input
fallback paths.

## Step 0: Classify the input

Look at `$ARGUMENTS` and pick exactly one path:

1. **Looks like an MR/PR URL** (`https://<host>/<project>/-/merge_requests/<id>` or
   `https://github.com/<owner>/<repo>/pull/<n>`), or a bare MR IID → **Step 1a (forge mode)**.
2. **A block of pasted text that isn't a URL** (the user pasted a title + description, possibly
   with a link buried inside it) → **Step 1b (pasted-description mode)**. If a URL happens to be
   embedded in the pasted text, you may still try Step 1a's fetch for the diff/comments, but use
   the pasted text as the description — don't overwrite it with whatever the API returns.
3. **No argument at all** → **Step 1c (no-MR fallback)**.

If forge mode fails (`glab`/`gh` reports not found, wrong project/repo, not installed or not
authenticated), don't error out — fall back to Step 1b if the user gave you description text, or
Step 1c otherwise. **Never silently default to diffing bare `HEAD`** with no context.

## Step 1a: Setup (forge mode — GitLab MR or GitHub PR)

Check for uncommitted work first:

```bash
git status --porcelain
```

- **Dirty working tree**: use `review`, which creates a separate worktree so in-progress work is
  undisturbed:
  ```bash
  "${CLAUDE_PLUGIN_ROOT}"/skills/code-review-local/scripts/git-utils.sh review <MR-ID|MR-URL|PR-URL>
  ```
- **Clean working tree**: `clone` checks out the MR/PR branch directly in place:
  ```bash
  "${CLAUDE_PLUGIN_ROOT}"/skills/code-review-local/scripts/git-utils.sh clone <MR-URL|PR-URL>
  ```
- **Reviewing an MR/PR from a different repo than the one open here**: `clone` also handles
  that — it clones into `$WORKSPACE` (default `~/workspace`) and checks out the branch.

If the script exits early (closed, merged, draft) or reports the MR/PR wasn't found, stop and
fall back to Step 1b (if description text is available) or Step 1c.

## Step 1b: Setup (pasted description, no usable forge lookup)

Use the pasted text verbatim as the MR/PR summary and description — this stands in for what
Step 1a's `glab`/`gh` fetch would otherwise provide. You still need a diff, so ask the user with
**AskUserQuestion**, in one call:

1. **Target branch to diff against** — offer the repo's default branch (`git symbolic-ref
   refs/remotes/origin/HEAD` or `main`/`master` if that fails), the current branch's upstream
   tracking branch if set (`git rev-parse --abbrev-ref --symbolic-full-name @{u}`), and let
   "Other" cover anything else.

Assume the branch already checked out locally (or the uncommitted working tree) is the change
being reviewed — that's the point of a local-only review: the user has the code checked out and
is pasting its description rather than pointing you at a live MR/PR. Once you have the target
branch, compute the diff — this single command captures everything since the branch diverged,
both committed and uncommitted:

```bash
git diff "$(git merge-base HEAD <target-branch>)"
```

If that's empty, tell the user there's nothing to review against `<target-branch>` rather than
reporting "no issues found".

## Step 1c: Setup (no MR/PR, no pasted description)

Don't guess the target branch or the intent silently. Ask the user with **AskUserQuestion**, in
one call, two questions:

1. **Target branch to diff against** — same options as Step 1b.
2. **What this change does** — propose a short candidate description inferred from
   `git log <target>..HEAD --oneline` (or `git diff --stat` if there are no commits yet, just
   uncommitted work), and let the user confirm it or replace it via "Other".

Then compute the diff the same way as Step 1b.

## Step 2: Review the Diff

Launch 3 **`code-reviewer`** agents in parallel via the Agent tool, each with a different focus,
given:

- MR/PR summary and description — from the setup script's output (Step 1a), or the pasted/
  confirmed text (Step 1b/1c)
- Related issue context — title, description, comments (Step 1a only, when the lookup succeeded)
- Existing MR/PR comments, so it doesn't re-flag already-raised issues (Step 1a only)
- The diff itself — pass the actual diff text or the command to reproduce it
  (`git diff "$(git merge-base HEAD <target-branch>)"` for Step 1b/1c)
- Instruction to focus on:
  - **Real bugs** — logic errors, broken edge cases, incorrect assumptions
  - **CLAUDE.md violations** — check project CLAUDE.md and any in directories touched by the diff
  - **Unaddressed prior comments** — anything raised before that's still unresolved (Step 1a only)
  - Skip: style nitpicks, issues on unmodified lines, things CI catches (type errors, lint,
    formatting)

The three focuses: (1) simplicity/DRY/elegance, (2) bugs/functional correctness, (3) project
conventions/abstractions. Each agent call returns a list of issues with file locations — collect
all three as input for Step 3.

## Step 3: Present Findings to User

Show the review summary in chat. This is the final deliverable — there is no Step 4. Format:

**If issues found:**

```
### Code review

Found N issue(s):

1. <brief description>
   https://<repo-url>/-/blob/<full-sha>/src/path/to/file.tsx#L45-48   (forge mode, GitLab)
   -- or --
   https://github.com/<owner>/<repo>/blob/<full-sha>/src/path/to/file.tsx#L45-L48   (forge mode, GitHub)
   -- or --
   path/to/file.tsx:45-48   (pasted-description or no-MR mode — no forge to link against)

2. ...
```

**If no issues:**

```
### Code review

No issues found.
```

**Linking rules (Step 1a, forge lookup succeeded):**

- Base URL: the `Repo:` value printed by the setup script.
- SHA: `git rev-parse HEAD` in the worktree/checkout the script created.
- GitLab format: `<repo-url>/-/blob/<sha>/path/to/file#L<start>-<end>` (no second `L` before end
  line). GitHub format: `<repo-url>/blob/<sha>/path/to/file#L<start>-L<end>` (GitHub does use a
  second `L`) — don't mix the two conventions up.
- Include 1 line of context before and after the relevant lines.

**Step 1b/1c (pasted description or no MR)**: no forge to link against, so cite
`path/to/file:<line>` instead of a blob URL.

Nothing in this skill posts, comments, approves, or otherwise writes back to any MR, PR, or
Slack channel — under any circumstance, even on user confirmation. If the user explicitly asks
you to post the review somewhere, tell them this skill is local-only by design and that they
should use `glab`/`gh` directly if they want it posted. The only optional next step here is
offering to save the findings to a local file — ask with **AskUserQuestion** only if it seems
useful (e.g. a long review the user may want to paste into a real MR/PR description or comment
by hand later).

`git-utils.sh review` removes its worktree automatically after collecting the diff; `git-utils.sh
clone` leaves the checkout in place under `$WORKSPACE` for follow-up inspection.
