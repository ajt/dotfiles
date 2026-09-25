# codex/

Codex CLI integration, mirroring `claude/`.

- `hooks.example.json` — template for `~/.codex/hooks.json`. Wires the `Stop`
  hook to `bin/codex-tmux-hook`, which records the session's rollout transcript
  on the tmux window (`@agent_transcript`) so `prefix R` opens Codex's last
  reply in the reader view, exactly as it does for Claude Code. Copy it into
  place by hand (or merge into an existing `hooks.json`); `symlink-setup.sh`
  does not touch `~/.codex`. Do not repurpose `notify` in `config.toml` for
  this: that is a single-slot mechanism and may already be in use.
