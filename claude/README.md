# claude

User-scope [Claude Code](https://docs.claude.com/claude-code) config that's safe to share publicly. Files in this directory are wired up by `symlink-setup.sh`.

## What's tracked

| File | How it's installed | Why |
|---|---|---|
| `statusline-command.sh` | **Symlinked** to `~/.claude/statusline-command.sh` | Pure stdin-driven renderer, no secrets, fine to live-sync across machines |
| `settings.example.json` | **Copied once** to `~/.claude/settings.json` if the target doesn't exist; never overwrites | The real `settings.json` accumulates per-machine state (enabled plugins, marketplaces, security flags) — keeping it out of public VC |
| `skills/prototype/` | **Symlinked** to `~/.claude/skills/prototype` | Pure-instruction skill (no scripts, no secrets), fine to live-sync across machines |

## What's deliberately *not* in here

- `~/.claude/settings.json` once it exists on a machine. The script copies the example as a starting point and walks away. Edit freely per machine.
- `~/.claude.json` (MCP config, lives in `$HOME`) — often has private endpoints; manually managed.
- `~/.claude/.credentials.json`, `sessions/`, `history.jsonl`, `cache/`, `plugins/`, `projects/` — runtime state, secrets, transcripts. Never publish.
- Plugin `.env` files (live in each plugin's data dir) — API keys.
- Custom skills under `~/.agents/skills/` — manage as their own private project if you ever build any worth keeping. (Skills worth sharing publicly live here under `skills/` instead — see `skills/prototype/`.)

## skills/prototype

Personal skill: parallel design-variant gallery. Given a UI brief, spawns 5+
subagents (each on a divergent named design direction, each using the
frontend-design skill), writes self-contained HTML variants to
`.prototypes/<slug>/round-N/` in the target project, and opens a gallery for
side-by-side comparison. The gallery is a shipped app
(`skills/prototype/assets/gallery-template.html`; rounds write a `variants.js`
data file) with viewport toggles (390/768/full), a light/dark switch (variants
ship both palettes via `?theme=`), per-card pick★/notes with a copy-feedback
button, an A/B compare overlay, and a props-knobs strip for React variants
(postMessage). Generation reads real project data when referenced, and
constrains part of the round to the project's design tokens when found.
Iteration classifies feedback as surgical (direct edits), directional
(interpretation fan-out), or remix (combine named variants); each round
appends to `.prototypes/<slug>/DECISIONS.md` and archives screenshots to
`round-N/shots/` when a browser tool is available. A final winner gets
promoted to a real component, with the decision record offered alongside.
Deployed to `~/.claude/skills/prototype` by `symlink-setup.sh`.
Spec: `docs/superpowers/specs/2026-06-12-prototype-skill-design.md`.

## Before publishing edits to `settings.example.json`

This file is **public**. Review for:

- **`skipAutoPermissionPrompt`** — security-posture flag; publishing it broadcasts your tolerance. Leave it out of the template; set per machine.
- **`extraKnownMarketplaces`** — only include public marketplace URLs. Private marketplace repos (e.g. `your-org/private-marketplace`) belong in the per-machine `settings.json`, not the template.
- **`enabledPlugins`** — same: only include public plugins.
- **Hook commands** — fine to publish references to public scripts (`~/.agents/skills/...`); avoid references to proprietary paths.

## Per-machine setup checklist

After `./symlink-setup.sh` runs:

1. Open `~/.claude/settings.json` and add anything machine-specific (private marketplaces, security flags).
2. Add private marketplace URLs via `/plugin marketplace add <owner>/<repo>` rather than hand-editing if you can — Claude writes the entry for you.
3. Drop any plugin `.env` files into their respective plugin data dirs (find with `/plugin info <name>`).
