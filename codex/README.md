# codex/

Codex CLI integration, mirroring `claude/`.

- `hooks.json` — symlinked to `~/.codex/hooks.json` by `symlink-setup.sh`
  (live-synced across machines, like `.tmux.conf`). Wires the `Stop` hook to
  `bin/codex-tmux-hook`, which records the session's rollout transcript on
  the tmux window (`@agent_transcript`) so `prefix R` opens Codex's last reply
  in the reader view, exactly as it does for Claude Code. Add further Codex
  hooks here, not in the symlink target.

`~/.codex/config.toml` stays per-machine and is never touched: it carries
`notify` integrations, model and trust settings. If Codex on a machine gates
hooks behind a feature flag, that is the one line to add there by hand
(`[features] codex_hooks = true`, unverified as of 2026-09-25). Do not
repurpose `notify` for the reader view: it is single-slot and may be in use.
