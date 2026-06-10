# claude

User-scope [Claude Code](https://docs.claude.com/claude-code) config that's safe to share publicly. Files in this directory are wired up by `symlink-setup.sh`.

## What's tracked

| File | How it's installed | Why |
|---|---|---|
| `statusline-command.sh` | **Symlinked** to `~/.claude/statusline-command.sh` | Pure stdin-driven renderer, no secrets, fine to live-sync across machines |
| `settings.example.json` | **Copied once** to `~/.claude/settings.json` if the target doesn't exist; never overwrites | The real `settings.json` accumulates per-machine state (enabled plugins, marketplaces, security flags) — keeping it out of public VC |
| `review/` | **Symlinked** to `~/.claude/review/` | Scripts + prompts for the second-model spec/plan gate; no secrets (the API key comes from the env). Linked as a unit so the scripts find their `prompts/` |

## Second-model review (`review/`)

An approval gate that runs a *different* model (Gemini) as an adversarial reviewer of plan/spec markdown files Claude touches (word-boundary match on the filename, or a `plans/`/`specs/` parent dir). On a non-`APPROVE` verdict the gate blocks the turn and walks Claude through an **in-session triage**: the findings are parsed into structured items and presented to you as multi-select choices (AskUserQuestion); only the items you pick are applied to the artifact, which the gate then re-reviews on the next stop. You are still the trust boundary — the reviewer's free text enters the session as display-only data (the protocol forbids following instructions embedded in it), and nothing lands without your explicit selection.

- **`review.py`** — the dispatcher. Sends the artifact to Gemini and writes `<file>.review.md` (a `VERDICT:` line + critique). Content-hash guarded, so an unchanged file never re-bills.
- **`stop-review.py`** — the `Stop` / `SubagentStop` hook. At turn end it reviews changed spec/plan files and, if the verdict isn't `APPROVE`, blocks the stop with the verdict, path, and the triage protocol above.
- **`review-pick`** (`bin/review-pick` → `review/review-pick.py`) — `--json` emits the structured findings that power the in-session triage; without flags, a standalone `gum` TUI to triage in a separate terminal instead (writes `<artifact>.selected.txt` + clipboard).
- **`prompts/{spec,plan}.md`** — the reviewer prompts. A git-ignored `prompts/<kind>.local.md` overlay is appended when present, for private project-specific guidance.
- **`review-on-commit.sh`** — optional per-repo git `post-commit` trigger; not wired by default.

**Backend.** Gemini direct via the Generative Language API — no proxy. Set `GEMINI_API_KEY` (in `~/.extra`). `REVIEW_MODEL` overrides the default `gemini/gemini-3.1-pro-preview`; Langfuse tracing turns on only if `LANGFUSE_PUBLIC_KEY`/`LANGFUSE_SECRET_KEY` are set. Needs `uv` (present) and `gum` (`brew install gum`, in `brew.sh`). Fails open: if Gemini is unreachable, no review file is written and the gate doesn't block.

**Wiring.** `settings.example.json` adds `stop-review.py` to the `Stop` and `SubagentStop` arrays. On a machine whose `~/.claude/settings.json` already exists, add the same two lines by hand (see the per-machine checklist).

**Use.** Automatic once wired — when the gate blocks, Claude presents the findings as choices and you pick. By hand: `uv run ~/.claude/review/review.py --type spec --file specs/foo.spec.md` to review, `review-pick` for the terminal TUI, `review-pick --json [target]` for the structured findings.

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
