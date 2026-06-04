# Consolidate the tmux + Claude Code integration — design

Date: 2026-06-04
Status: approved, pre-implementation
Branch: `feature/claude-tmux-integration`

## Problem

Over the last day, three tmux/Claude features were built across several branches and an
uncommitted working tree. They are partly merged, partly in an open PR, and partly
untracked. The result: a fresh clone is broken, an open PR carries a regression, and the
machine's live state diverges from the repo. The goal is to land the complete integration
on `main` as one coherent, publicly-shareable unit while keeping the live machine working
and keeping machine-private state out of version control.

### Current state (as surveyed)

- **Worktree notice** — `bin/tmux-worktree-notice`, the `⧉` tab marker, `prefix b` toggle.
  On `main`, live, working.
- **Auto-label hook** — `bin/claude-tmux-notice`, names a window from the first prompt.
  On `main`, live, working (PR #4, merged).
- **Per-tab state indicator** — exists in two competing versions:
  - **Binary** (`@claude_waiting`, orange-when-waiting): live on the machine and wired by
    the *untracked* `claude/settings.example.json`.
  - **Tiered** (`@claude_state`: working/subagent/compacting/waiting/done/idle) via the new
    `bin/claude-tmux-state`: PR #3 (`claude-tmux-state`), not live. It rewrites the same
    `.tmux.conf` line and the same `settings.example.json`, so it is a **replacement**.

### Structural issues

1. **Fresh clone is broken.** `symlink-setup.sh` on `main` references `claude/statusline-command.sh`
   and `claude/settings.example.json`, but the entire `claude/` directory is untracked.
   The wiring is public; the payload is not.
2. **PR #3 collides with the untracked `claude/`** and carries a **regression**: its tiered
   `settings.example.json` drops the `~/bin/claude-tmux-notice` auto-label hook that landed
   later via PR #4. PR #3 also contains only the settings file (not `README.md` /
   `statusline-command.sh`).
3. **Live `~/.claude/settings.json` holds machine-private state** not in the public template:
   extra plugins (`swift-lsp`, `context7`, `superpowers`), an `axiom-marketplace`
   (`CharlesWiltgen/Axiom`), and `skipAutoPermissionPrompt: true` — the exact security flag
   `claude/README.md` says must never be published. It must never be overwritten wholesale.
4. **Uncommitted bits:** `.tmux.conf` truecolor line (`set -as terminal-features ',*:RGB'`,
   safe/public) and `.zshrc` `CLAUDE_TMUX_NOTICE_WORDS=10` (personal tuning; repo default 6).

## Decisions

- **Tiered `@claude_state` replaces binary `@claude_waiting`** as the single state system.
- **`CLAUDE_TMUX_NOTICE_WORDS=10` moves to the git-ignored `~/.extra`**; public `.zshrc`
  reverts to the documented default (6).
- **Mechanism: one fresh consolidation PR** off `main`; **PR #3 closed as superseded**.

## Design

### What lands in the repo (public, shareable)

- **`claude/` directory committed in full:** `README.md`, `statusline-command.sh`, and a
  **reconciled** `settings.example.json`.
- **`bin/claude-tmux-state`** (content reused from PR #3).
- **`.tmux.conf`:** truecolor RGB line + the `@claude_state` window-status rewrite, with the
  dead `@claude_waiting` line removed.
- **Design/plan docs** from PR #3 — the design spec under `docs/superpowers/specs/` and the
  implementation plan under `docs/superpowers/plans/` (plus this spec).

### The reconciled `claude/settings.example.json` (the crux)

A single public template wiring all three features, fixing the PR #3 regression. Hooks:

- `SessionStart` → `~/bin/claude-tmux-state SessionStart`
- `PreToolUse` → Bash-matched adversarial `hook-gate.sh` **+** `~/bin/claude-tmux-state PreToolUse`
- `UserPromptSubmit` → adversarial `hook-challenge.sh` **+** `~/bin/claude-tmux-state UserPromptSubmit`
  **+** `~/bin/claude-tmux-notice`  ← reconciliation: restores the dropped auto-label hook
- `Notification` → `~/bin/claude-tmux-state Notification`
- `SubagentStart` → `~/bin/claude-tmux-state SubagentStart`
- `SubagentStop` → `~/bin/claude-tmux-state SubagentStop`
- `PreCompact` → `~/bin/claude-tmux-state PreCompact`
- `Stop` → `~/bin/claude-tmux-state Stop`
- `SessionEnd` → `~/bin/claude-tmux-state SessionEnd`
- `statusLine` → `bash ~/.claude/statusline-command.sh`

Included (non-secret, already in the authored template): `permissions.defaultMode: auto`,
`enabledPlugins: frontend-design`, `extraKnownMarketplaces: anthropics/skills`,
`effortLevel/verbose/agentPushNotifEnabled`.

**Excluded** (per `claude/README.md` publish rules): `skipAutoPermissionPrompt`, the private
plugins (`swift-lsp`, `context7`, `superpowers`), and `axiom-marketplace`.

The set of wired events must match the `case` arms in `bin/claude-tmux-state`.

### Git sequence

New branch `feature/claude-tmux-integration` off `main`, so `main..HEAD` contains only these
commits (per the parallel-session contamination rule). Logical commits:

1. Add `claude/` public config: `README.md` + `statusline-command.sh`.
2. Add the reconciled `claude/settings.example.json`.
3. Add `bin/claude-tmux-state` (reuse PR #3's content).
4. `.tmux.conf`: truecolor RGB line + `@claude_state` window-status rewrite, removing the dead
   `@claude_waiting` line.
5. Add PR #3's design spec (`docs/superpowers/specs/`) and implementation plan
   (`docs/superpowers/plans/`).

Open the consolidation PR. **`CLAUDE.md` is git-excluded in this repo** — no `CLAUDE.md`
changes go in any commit; feature docs live in `docs/` and `claude/README.md`.

### Live-machine sync (after the branch is built)

- **Surgical hook swap:** back up `~/.claude/settings.json`, then `jq` to set `.hooks` (and
  confirm `.statusLine`) from the reconciled template, leaving `enabledPlugins`,
  `extraKnownMarketplaces`, `skipAutoPermissionPrompt`, etc. untouched.
- **`~/.extra`:** add `export CLAUDE_TMUX_NOTICE_WORDS=10`; revert the `.zshrc` line to default.
- **Reload:** `tmux source-file ~/.tmux.conf`.

### Verification (evidence before "done")

- Run the `tests/` bash harness.
- `jq empty` on both the template and the live settings; diff live settings to confirm only
  `.hooks` / `.statusLine` changed and `skipAutoPermissionPrompt` survived.
- **State-render matrix:** for each event, run `~/bin/claude-tmux-state <event>` in a pane and
  confirm the expected tab glyph/color: `working ◐`, `subagent ⊕`, `compacting ⟳`,
  `waiting ?` (orange fill), `done ✓`, idle (quiet bar). Plus one real end-to-end (Claude asks
  → tab goes orange).
- Fresh-clone / re-run sanity: `symlink-setup.sh` no longer prints `SKIP claude/*`.

### Cleanup

- Delete merged `feature/tmux-worktree-notice` and superseded
  `feature/claude-tmux-autonotice-mixed` (local, and remote if pushed).
- Close PR #3 referencing the new PR.
- Issue #2 ("clear Claude 'done' state on tab focus") stays open — **out of scope**.

## Risks & mitigations

- **Per-machine state clobbered** → jq splice of `.hooks` only, backup first, diff after.
- **Invalid JSON** → `jq empty` on template and live file before relying on them.
- **`.tmux.conf` not reloaded** → explicit `tmux source-file` step.
- **Event/case mismatch** → state-render matrix covers every wired event.
- **Contaminated branch** → branch fresh off `main`; verify `main..HEAD` before opening the PR.

## Out of scope

- Issue #2 (clear `done` on tab focus).
- Any change to `CLAUDE.md` (git-excluded here).
- Refactoring `bin/claude-tmux-state` beyond what PR #3 already implements.
