# claude-plugins

Personal collection of Claude Code skills + GitHub Copilot prompt bundles (private repo). One
folder per tool under `tools/`. Despite the repo name, these are installed as **standalone Claude
Code skills** (`~/.claude/skills/`), not Claude Code plugins — that trade-off is explained in each
tool's own README, but the short version: a plugin-shipped skill is always invoked as
`/plugin-name:skill-name` (a Claude Code platform rule, no way around it), while a standalone
skill in `~/.claude/skills/` gets a bare command name and is still available in every project on
the machine. Where a tool's functionality also makes sense in GitHub Copilot, it ships a
`copilot/` subfolder with the Copilot-equivalent prompt file plus a small install script — Copilot
has no plugin-installer of its own, so that's a manual copy into the target repo's `.github/`
folder.

## Installing a tool — Claude Code (one time, per machine)

```bash
git clone https://github.com/vishal-maheshshivashankar/claude-plugins.git
./claude-plugins/tools/<tool-name>/install-claude.sh
```

This symlinks the tool's skill (and any agent it depends on) into `~/.claude/skills/` and
`~/.claude/agents/`. Because it's a symlink, a later `git pull` in this repo updates what's
installed automatically. It's then available as a bare `/<tool-name>` command in every project on
this machine — no per-project setup, no marketplace step.

## Installing a tool's Copilot bundle (per repo)

```bash
./claude-plugins/tools/<tool-name>/install-copilot.sh /path/to/target/repo
```

Unlike the Claude Code install above, this is per-repo — re-run it for each repo you want the
Copilot prompt in. See each tool's own README for exact commands and an experimental one-time
global install option.

## Tools

| Tool | Description |
|---|---|
| [`code-reviewer`](tools/code-reviewer) | Local-only MR/PR review (GitLab MR, GitHub PR, pasted description, or local branch diff) — reports findings only in chat, never posts back to the MR/PR. `/code-reviewer` in Claude Code, `/code-review` in Copilot (per-repo install). |

## Adding a new tool

1. `mkdir -p tools/<name>/skills/<name>` and add a `SKILL.md` there (frontmatter `name:` should
   match `<name>` so the installed command matches the folder).
2. Add `agents/` if the skill depends on a sub-agent, following the shape in
   `tools/code-reviewer/agents/code-reviewer.md`.
3. Add `install-claude.sh` (copy `tools/code-reviewer/install-claude.sh` and adjust the
   name/paths) so the tool installs the same way as the others.
4. If it has a Copilot equivalent, put it under `tools/<name>/copilot/` with its own
   `install-copilot.sh`, matching `code-reviewer`'s layout.
5. Add a row to the table above and commit.
