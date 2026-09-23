---
agent: agent
description: Review a GitLab MR / GitHub PR (URL or ID), a pasted MR/PR description, or the current local branch's changes — and report findings only in this chat. Never posts a comment, review, or approval back to the MR/PR.
tools: ['search/codebase', 'search', 'web/githubRepo', 'read/problems', 'vscodeTasks/problems']
---

# Local Code Review (Copilot)

Input for this review (a GitLab MR URL, a GitHub PR URL, a bare MR ID, a pasted MR/PR
description, or nothing): ${input:target}

This is the Copilot Chat equivalent of the Claude Code skill at
`.claude/skills/code-review-local/SKILL.md` in this same folder — same steps, same
confidence-based filtering, same output format. The one thing that differs from Copilot's own
default PR-review behavior: **this never posts anything back to the MR/PR.** Every result of
running this prompt is a chat message in this session, full stop — no submitted review, no
comment, no approval, regardless of what you find or how confident you are.

> **Terminal access**: this prompt needs to run `git`, `gh`, and/or `glab` commands. VS Code's
> tool-naming for shell execution changes across Copilot versions, so it's deliberately not
> pinned in the `tools:` list above — if this prompt can't run shell commands in your setup,
> enable your Copilot terminal/"run in terminal" tool for this chat manually before using it.

## Step 0 — classify the input

- Looks like an MR/PR URL, or a bare MR IID → **forge mode**.
- Non-URL pasted text (title + description, maybe with a link inside it) → **pasted-description
  mode**. Use the pasted text as the description directly; don't try to re-fetch it.
- Empty/no input → **local-diff mode**.

If forge mode fails (no `gh`/`glab` on PATH, not authenticated, repo/MR not found), fall back to
pasted-description mode if you have text to work with, otherwise local-diff mode. Don't silently
diff bare `HEAD` with no context — always establish a target branch first.

## Step 1 — get the diff and context

**Forge mode (GitHub PR):** use the `githubRepo` tool / `gh pr view <n> --json title,body,...`
and `gh pr diff <n>` (via the terminal tool) to fetch the PR's title, description, comments, and
diff.

**Forge mode (GitLab MR):** use `glab mr view <id> --comments --output json` and
`glab mr diff <id>` (via the terminal tool) the same way.

**Pasted-description mode:** ask the user (in chat, since Copilot prompt files don't have a
structured question tool) which branch to diff against — offer the repo's default branch and the
current branch's upstream tracking branch as the obvious choices. Then run:

```
git diff "$(git merge-base HEAD <target-branch>)"
```

**Local-diff mode:** same as pasted-description mode, but also ask the user for a one-line
description of what the change does (propose one inferred from `git log <target>..HEAD --oneline`
and let them confirm or correct it) before you start reviewing — this stands in for the missing
MR/PR description.

If the resulting diff is empty, say so plainly instead of reporting "no issues found".

## Step 2 — review the diff

Review it yourself in three sequential passes (Copilot Chat has no parallel subagents, so do
these one after another rather than concurrently):

1. **Simplicity / DRY / elegance** — unnecessary abstraction, duplicated logic, over-engineering.
2. **Bugs / functional correctness** — logic errors, broken edge cases, incorrect assumptions,
   security issues.
3. **Project conventions** — violations of this repo's own `CLAUDE.md`/`copilot-instructions.md`
   (check the root and any in directories the diff touches), naming, error handling, and existing
   architectural patterns.

For each candidate issue, apply the same confidence-based filter code-reviewer agents use
elsewhere in this workflow: rate your confidence 0–100 (0 = false positive / pre-existing issue,
100 = certain, will happen in practice) and **only report issues at confidence ≥ 80**. Quality
over quantity — skip style nitpicks, issues on unmodified lines, and anything CI/lint/type-check
would already catch. If forge mode gave you existing MR/PR comments, don't re-report issues
already raised there.

## Step 3 — report in chat (this is the entire deliverable)

**If issues found:**

```
### Code review

Found N issue(s):

1. <brief description> (confidence: NN)
   path/to/file.ext:<line-start>-<line-end>
   <why it's a problem, and a concrete fix>

2. ...
```

**If no issues:**

```
### Code review

No issues found.
```

Do not open a PR review, submit review comments, approve, or request changes — even if asked to,
even if you're fully confident. If the user wants the review posted, tell them this prompt is
local-only by design and point them at `gh pr review` / `glab mr note` (or the org's normal
review flow) to do that themselves. The only optional follow-up is offering to save this report
to a local markdown file if the user wants to paste it in elsewhere by hand.
