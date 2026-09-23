# claude-plugins

Personal marketplace of Claude Code plugins (private). One folder per plugin under `plugins/`,
catalogued in `.claude-plugin/marketplace.json`. Where a plugin's functionality also makes sense
in GitHub Copilot, it ships a `copilot/` subfolder with the Copilot-equivalent prompt file plus a
small install script — Copilot has no plugin-installer of its own, so that's a manual copy into
the target repo's `.github/` folder rather than a one-line install.

## Using this as a Claude Code plugin marketplace

From any machine, in any Claude Code session:

```
/plugin marketplace add vishal-maheshshivashankar/claude-plugins
/plugin install <plugin-name>
```

This is a one-time, machine-wide install: once installed, a plugin is available in every project
you open on that machine afterwards, not just the one you ran the command in. Plugin skills are
always namespaced as `/plugin-name:skill-name` (Claude Code's own collision-prevention design),
so e.g. `code-review`'s skill is invoked as `/code-review:local`, not a bare `/code-review`.

To update after this repo changes:

```
/plugin marketplace update vishalm-claude-plugins
```

## Using a plugin's Copilot bundle

For plugins that ship a `copilot/` subfolder, install it into whichever repo you want it in:

```bash
git clone https://github.com/vishal-maheshshivashankar/claude-plugins.git
./claude-plugins/plugins/<plugin-name>/install-copilot.sh /path/to/target/repo
```

Unlike the Claude Code plugin install above, this is per-repo — re-run it for each repo you want
the Copilot prompt in. See each plugin's own README for exact commands and an experimental
one-time global install option.

## Plugins

| Plugin | Description |
|---|---|
| [`code-review`](plugins/code-review) | Local-only MR/PR review (GitLab MR, GitHub PR, pasted description, or local branch diff) — reports findings only in chat, never posts back to the MR/PR. Invoke as `/code-review:local`. Copilot bundle included (`/code-review` there, per-repo install). |

## Adding a new plugin

1. `mkdir -p plugins/<name>/.claude-plugin` and add a `plugin.json` (`name` is the only required
   field; see any existing plugin for the fuller shape).
2. Add `skills/`, `agents/`, `commands/`, or `hooks.json` as needed, following the [plugin
   directory conventions](https://code.claude.com/docs/en/plugins-reference).
3. Add an entry to `.claude-plugin/marketplace.json`'s `plugins` array with `name` and
   `source: "./plugins/<name>"`.
4. If it has a Copilot equivalent, put it under `plugins/<name>/copilot/` with its own
   `install-copilot.sh`, matching `code-review`'s layout.
5. Commit and push — `/plugin marketplace update` on any installed machine picks it up.
