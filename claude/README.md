# claude

User-scope [Claude Code](https://docs.claude.com/claude-code) config that's safe to share publicly. Files in this directory are wired up by `symlink-setup.sh`.

## What's tracked

| File | How it's installed | Why |
|---|---|---|
| `statusline-command.sh` | **Symlinked** to `~/.claude/statusline-command.sh` | Pure stdin-driven renderer, no secrets, fine to live-sync across machines |
| `settings.example.json` | **Copied once** to `~/.claude/settings.json` if the target doesn't exist; never overwrites | The real `settings.json` accumulates per-machine state (enabled plugins, marketplaces, security flags) — keeping it out of public VC |
| `review/` | **Symlinked** to `~/.claude/review/` | Scripts + prompts for the second-model spec/plan gate; no secrets (the API key comes from the env). Linked as a unit so the scripts find their `prompts/` |

## Second-model review (`review/`)

An approval gate that runs a *different* model (Gemini) as an adversarial reviewer of plan/spec markdown files Claude touches (word-boundary match on the filename, or a `plans/`/`specs/` parent dir). On a non-`APPROVE` verdict the gate blocks the turn and hands Claude the findings to handle **in-session, autonomously**: Claude sanity-checks each finding on its merits, applies the ones that survive scrutiny to the artifact, reports what it applied and what it rejected (and why), and continues; the gate re-reviews the updated file on the next stop. The reviewer's free text enters the session, but as data to be judged — the protocol forbids following instructions embedded in it, and nothing is accepted on the second model's authority alone.

- **`review.py`** — the dispatcher. Sends the artifact to Gemini and writes `<file>.review.md` (a `VERDICT:` line + critique). Content-hash guarded, so an unchanged file never re-bills.
- **`stop-review.py`** — the `Stop` / `SubagentStop` hook. At turn end it reviews changed spec/plan files and, if the verdict isn't `APPROVE`, blocks the stop with the verdict, path, and the handling protocol above.
- **`review-pick`** (`bin/review-pick` → `review/review-pick.py`) — `--json` emits the structured findings that power the in-session handling; without flags, a standalone `gum` TUI for hand-curated triage in a separate terminal (writes `<artifact>.selected.txt` + clipboard).
- **`prompts/{spec,plan}.md`** — the reviewer prompts. A git-ignored `prompts/<kind>.local.md` overlay is appended when present, for private project-specific guidance.
- **`review-on-commit.sh`** — optional per-repo git `post-commit` trigger; not wired by default.

**Backend.** Gemini direct via the Generative Language API — no proxy. Set `GEMINI_API_KEY` (in `~/.extra`). `REVIEW_MODEL` overrides the default `gemini/gemini-3.1-pro-preview`; Langfuse tracing turns on only if `LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY` are set. Needs `uv` (present) and `gum` (`brew install gum`, in `brew.sh`). Fails open: if Gemini is unreachable, no review file is written and the gate doesn't block.

**Wiring.** `settings.example.json` adds `stop-review.py` to the `Stop` and `SubagentStop` arrays. On a machine whose `~/.claude/settings.json` already exists, add the same two lines by hand (see the per-machine checklist).

**Use.** Automatic once wired — when the gate blocks, Claude sanity-checks the findings, updates the artifact, and tells you what it applied and rejected. By hand: `uv run ~/.claude/review/review.py --type spec --file specs/foo.spec.md` to review, `review-pick` for the terminal TUI, `review-pick --json [target]` for the structured findings.

## What's deliberately *not* in here

- `~/.claude/settings.json` once it exists on a machine. The script copies the example as a starting point and walks away. Edit freely per machine.
- `~/.claude.json` (MCP config, lives in `$HOME`) — often has private endpoints; manually managed.
- `~/.claude/.credentials.json`, `sessions/`, `history.jsonl`, `cache/`, `plugins/`, `projects/` — runtime state, secrets, transcripts. Never publish.
- Plugin `.env` files (live in each plugin's data dir) — API keys.
- Custom skills under `~/.agents/skills/` — manage as their own private project if you ever build any worth keeping.

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
4. **Second-model review:** put `export GEMINI_API_KEY=…` in `~/.extra` and `brew install gum`. If `~/.claude/settings.json` already existed (so the template wasn't copied), hand-merge the `stop-review.py` entries into your `Stop` and `SubagentStop` hook arrays — see `settings.example.json`.
