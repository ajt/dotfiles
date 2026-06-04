# tmux + Claude Code Integration Consolidation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the complete tmux/Claude-Code integration on `main` as one coherent, publicly-shareable unit, with the live machine fully working and machine-private state kept out of version control.

**Architecture:** A fresh branch (`feature/claude-tmux-integration`, already created off `main`) collects the public payload in focused commits: the `claude/` config dir (README, statusline, a *reconciled* settings template), the `bin/claude-tmux-state` script + its test, the `.tmux.conf` rewrite, and PR #3's docs. The machine is then synced by splicing only the hook block into the private `~/.claude/settings.json` (never overwriting it) and moving a personal tuning var into `~/.extra`. PR #3 is closed as superseded.

**Tech Stack:** bash, tmux, jq, git, gh, Claude Code hooks.

**Reference spec:** `docs/superpowers/specs/2026-06-04-claude-tmux-integration-consolidation-design.md`

---

## Pre-flight (already true; confirm before starting)

- Current branch is `feature/claude-tmux-integration` (run `git branch --show-current`).
- Working tree has: untracked `claude/` dir, modified `.tmux.conf` (truecolor line), modified `.zshrc` (`CLAUDE_TMUX_NOTICE_WORDS=10`). These get incorporated/reverted by the tasks below.
- The spec commit (`Add consolidation spec…`) is the only commit in `main..HEAD`.

## File Structure

Public payload landing in the repo:

- `claude/README.md` — public Claude config doc (exists untracked; commit as-is).
- `claude/statusline-command.sh` — symlinked statusline renderer (exists untracked; commit as-is).
- `claude/settings.example.json` — **authored fresh** here: reconciled public template.
- `bin/claude-tmux-state` — tiered tab-state hook helper (carried from `claude-tmux-state`).
- `tests/claude-tmux-state.test.sh` — its test, **renamed** to match the `*.test.sh` runner glob.
- `.tmux.conf` — truecolor line + `@claude_state` window-status rewrite (drop `@claude_waiting`).
- `docs/superpowers/specs/2026-06-03-claude-tmux-state-design.md`,
  `docs/superpowers/plans/2026-06-03-claude-tmux-state.md` — carried from `claude-tmux-state`.

Machine-only (not in VC):

- `~/.claude/settings.json` — hook block spliced in; private state preserved.
- `~/.extra` — gains `export CLAUDE_TMUX_NOTICE_WORDS=10`.
- `.zshrc` — working-tree change reverted to the committed default.

---

## Task 1: Commit the `claude/` public payload (README + statusline)

**Files:**
- Add: `claude/README.md`
- Add: `claude/statusline-command.sh`

- [ ] **Step 1: Confirm the two files exist and are the only ones staged**

Run:
```bash
git add claude/README.md claude/statusline-command.sh
git status --porcelain claude/
```
Expected: `A  claude/README.md` and `A  claude/statusline-command.sh`. (Note: `claude/settings.example.json` is intentionally *not* added here — Task 2 replaces it with the reconciled version. If `git status` shows it staged, run `git restore --staged claude/settings.example.json`.)

- [ ] **Step 2: Confirm statusline is executable**

Run:
```bash
test -x claude/statusline-command.sh && echo OK
```
Expected: `OK`. If not: `chmod +x claude/statusline-command.sh && git add claude/statusline-command.sh`.

- [ ] **Step 3: Commit**

```bash
git commit -m "Add public claude/ config dir (README + statusline)"
```

---

## Task 2: Author the reconciled `claude/settings.example.json`

This fixes the PR #3 regression (restores the `~/bin/claude-tmux-notice` auto-label hook) and wires all `@claude_state` events. Excludes the security-posture flag, private plugins, and the private marketplace.

**Files:**
- Create/overwrite: `claude/settings.example.json`

- [ ] **Step 1: Write the file**

Write `claude/settings.example.json` with exactly this content:

```json
{
  "permissions": {
    "defaultMode": "auto"
  },
  "hooks": {
    "SessionStart": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SessionStart" } ] }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [ { "type": "command", "command": "bash ~/.agents/skills/adversarial-completion-review/hook-gate.sh" } ]
      },
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state PreToolUse" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash ~/.agents/skills/adversarial-completion-review/hook-challenge.sh" } ] },
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state UserPromptSubmit" } ] },
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-notice" } ] }
    ],
    "Notification": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state Notification" } ] }
    ],
    "SubagentStart": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SubagentStart" } ] }
    ],
    "SubagentStop": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SubagentStop" } ] }
    ],
    "PreCompact": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state PreCompact" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state Stop" } ] }
    ],
    "SessionEnd": [
      { "hooks": [ { "type": "command", "command": "~/bin/claude-tmux-state SessionEnd" } ] }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "enabledPlugins": {
    "frontend-design@claude-plugins-official": true
  },
  "extraKnownMarketplaces": {
    "anthropic-agent-skills": {
      "source": {
        "source": "github",
        "repo": "anthropics/skills"
      }
    }
  },
  "effortLevel": "xhigh",
  "verbose": true,
  "agentPushNotifEnabled": true
}
```

- [ ] **Step 2: Validate JSON + assert the reconciliation invariants**

Run:
```bash
jq empty claude/settings.example.json && echo "VALID JSON"
jq -e '.hooks.UserPromptSubmit | map(.hooks[].command) | any(. == "~/bin/claude-tmux-notice")' claude/settings.example.json >/dev/null && echo "auto-label hook present"
jq -e '.hooks | has("SessionStart") and has("SubagentStart") and has("SubagentStop") and has("PreCompact") and has("SessionEnd")' claude/settings.example.json >/dev/null && echo "state events wired"
jq -e 'has("skipAutoPermissionPrompt") | not' claude/settings.example.json >/dev/null && echo "no skipAutoPermissionPrompt"
jq -e '.enabledPlugins | keys == ["frontend-design@claude-plugins-official"]' claude/settings.example.json >/dev/null && echo "only public plugin"
jq -e '.extraKnownMarketplaces | keys == ["anthropic-agent-skills"]' claude/settings.example.json >/dev/null && echo "only the public marketplace"
```
Expected: all six lines print their success message.

- [ ] **Step 3: Commit**

```bash
git add claude/settings.example.json
git commit -m "Add reconciled claude settings template (tiered state + auto-label hooks)"
```

---

## Task 3: Add `bin/claude-tmux-state` and its test (carried from PR #3, test renamed)

**Files:**
- Add: `bin/claude-tmux-state` (from `claude-tmux-state` branch)
- Add: `tests/claude-tmux-state.test.sh` (from branch file `tests/test-claude-tmux-state.sh`, **renamed**)

- [ ] **Step 1: Bring the script over from the branch (preserves exec bit)**

Run:
```bash
git checkout claude-tmux-state -- bin/claude-tmux-state
test -x bin/claude-tmux-state && echo "executable OK"
```
Expected: `executable OK`.

- [ ] **Step 2: Syntax-check the script**

Run:
```bash
bash -n bin/claude-tmux-state && echo "syntax OK"
```
Expected: `syntax OK`.

- [ ] **Step 3: Bring the test over under the runner-matching name**

The branch named it `test-claude-tmux-state.sh`, which `tests/run.sh` (glob `*.test.sh`) would skip. Extract it to the correct name:
```bash
git show claude-tmux-state:tests/test-claude-tmux-state.sh > tests/claude-tmux-state.test.sh
test -s tests/claude-tmux-state.test.sh && echo "test file written"
```
Expected: `test file written`.

- [ ] **Step 4: Run the full test suite (the new test must be picked up and pass)**

Run:
```bash
bash tests/run.sh
```
Expected: output includes `== claude-tmux-state.test.sh` and ends with `ALL TESTS PASSED`.
If the runner does not list `claude-tmux-state.test.sh`, the filename is wrong — re-check Step 3.

- [ ] **Step 5: Commit**

```bash
git add bin/claude-tmux-state tests/claude-tmux-state.test.sh
git commit -m "Add claude-tmux-state tab-state helper and test"
```

---

## Task 4: Rewrite `.tmux.conf` window-status to `@claude_state` (keep truecolor line)

The working-tree `.tmux.conf` currently has the truecolor line + the *old* `@claude_waiting` window-status. We take the branch's `.tmux.conf` (new `@claude_state` window-status, but no truecolor line) and re-add the truecolor line.

**Files:**
- Modify: `.tmux.conf`

- [ ] **Step 1: Replace `.tmux.conf` with the branch version (has the new window-status)**

Run:
```bash
git checkout claude-tmux-state -- .tmux.conf
grep -c '@claude_state' .tmux.conf && echo "new window-status present"
grep -c '@claude_waiting' .tmux.conf || echo "old @claude_waiting gone"
```
Expected: `@claude_state` count ≥ 1; `@claude_waiting` count is 0 (the `|| echo` branch prints "old @claude_waiting gone").

- [ ] **Step 2: Re-insert the truecolor line**

Use the editor to insert the truecolor line immediately after the `default-terminal` line. Change:

```
set -g default-terminal "screen-256color"
setw -g xterm-keys on
```
to:
```
set -g default-terminal "screen-256color"
set -as terminal-features ',*:RGB'
setw -g xterm-keys on
```

- [ ] **Step 3: Verify both changes present**

Run:
```bash
grep -q "terminal-features ',\*:RGB'" .tmux.conf && echo "truecolor OK"
grep -q '@claude_state' .tmux.conf && echo "state window-status OK"
grep -q '@claude_waiting' .tmux.conf && echo "STILL HAS @claude_waiting (BAD)" || echo "no @claude_waiting OK"
```
Expected: `truecolor OK`, `state window-status OK`, `no @claude_waiting OK`.

- [ ] **Step 4: Commit**

```bash
git add .tmux.conf
git commit -m "Render tiered @claude_state on tmux tabs; enable truecolor"
```

---

## Task 5: Carry over PR #3's design spec and plan docs

**Files:**
- Add: `docs/superpowers/specs/2026-06-03-claude-tmux-state-design.md`
- Add: `docs/superpowers/plans/2026-06-03-claude-tmux-state.md`

- [ ] **Step 1: Bring both docs over from the branch**

Run:
```bash
git checkout claude-tmux-state -- \
  docs/superpowers/specs/2026-06-03-claude-tmux-state-design.md \
  docs/superpowers/plans/2026-06-03-claude-tmux-state.md
git status --porcelain docs/
```
Expected: both files show as added (`A`).

- [ ] **Step 2: Commit**

```bash
git commit -m "Add claude-tmux-state design spec and plan docs"
```

---

## Task 6: Sync the live machine (private state preserved)

No repo changes here — this makes the running machine match the new design without clobbering machine-private settings.

**Files:**
- Modify (machine-only): `~/.claude/settings.json`, `~/.extra`
- Revert (working tree): `.zshrc`

- [ ] **Step 1: Back up the live settings**

Run:
```bash
cp -v ~/.claude/settings.json ~/.claude/settings.json.bak
```
Expected: confirms the copy.

- [ ] **Step 2: Splice only `.hooks` and `.statusLine` from the reconciled template**

Run:
```bash
jq --slurpfile t claude/settings.example.json \
   '.hooks = $t[0].hooks | .statusLine = $t[0].statusLine' \
   ~/.claude/settings.json > /tmp/claude-settings.new.json
jq empty /tmp/claude-settings.new.json && echo "new settings valid JSON"
```
Expected: `new settings valid JSON`.

- [ ] **Step 3: Verify private state survives, then install**

Run:
```bash
# Machine-private settings (private plugins, marketplaces, security-posture flags) must survive
# untouched — Step 4's full diff is the authoritative proof. The quick positive checks here are
# just for the newly-wired hooks:
jq -e '.hooks.UserPromptSubmit | map(.hooks[].command) | any(. == "~/bin/claude-tmux-notice")' /tmp/claude-settings.new.json >/dev/null && echo "auto-label hook present"
jq -e '.hooks | has("SessionStart") and has("PreCompact")' /tmp/claude-settings.new.json >/dev/null && echo "state hooks present"
```
Expected: both success lines. Then install:
```bash
mv /tmp/claude-settings.new.json ~/.claude/settings.json
```

- [ ] **Step 4: Confirm only hooks/statusLine changed vs the backup**

Run:
```bash
diff <(jq -S 'del(.hooks, .statusLine)' ~/.claude/settings.json.bak) \
     <(jq -S 'del(.hooks, .statusLine)' ~/.claude/settings.json) && echo "ONLY hooks/statusLine changed"
```
Expected: no diff output, then `ONLY hooks/statusLine changed`.

- [ ] **Step 5: Move the tuning var to `~/.extra`; revert `.zshrc`**

Run:
```bash
grep -q CLAUDE_TMUX_NOTICE_WORDS ~/.extra || printf 'export CLAUDE_TMUX_NOTICE_WORDS=10\n' >> ~/.extra
grep -n CLAUDE_TMUX_NOTICE_WORDS ~/.extra
git checkout -- .zshrc
git diff --stat .zshrc | grep -q . && echo ".zshrc STILL DIRTY (BAD)" || echo ".zshrc reverted to default"
```
Expected: `~/.extra` shows the export line; `.zshrc reverted to default`.

- [ ] **Step 6: Reload tmux config**

Run:
```bash
tmux source-file ~/.tmux.conf && echo "tmux reloaded"
```
Expected: `tmux reloaded` with no error. (`~/.tmux.conf` is a symlink to the repo file, so the new window-status is now active.)

---

## Task 7: Verify the tab-state renders end to end

- [ ] **Step 1: Programmatic state matrix (script → @claude_state)**

Run each and confirm the reported value:
```bash
for ev in SessionStart:idle UserPromptSubmit:working Notification:waiting PreCompact:compacting Stop:done; do
  e=${ev%%:*}; want=${ev##*:}
  ~/bin/claude-tmux-state "$e"
  got=$(tmux show-options -wqv @claude_state)
  [ "$got" = "$want" ] && echo "$e -> $got OK" || echo "$e -> got '$got' want '$want' BAD"
done
```
Expected: five `... OK` lines. (Subagent state needs a real subagent; covered by the test suite in Task 3 and the live end-to-end below.)

- [ ] **Step 2: Visual confirmation**

After Step 1 the current window tab shows the `done ✓` styling. Run `~/bin/claude-tmux-state working` and visually confirm the tab shows the cyan `◐` working glyph; run `~/bin/claude-tmux-state Notification` and confirm it turns the orange `?` waiting fill. Then `~/bin/claude-tmux-state UserPromptSubmit` to leave it in `working`. (The live hooks will keep it correct from here.)

- [ ] **Step 3: Confirm the public payload is fully tracked (fresh-clone safety)**

Run:
```bash
git ls-files claude/ | sort
```
Expected: lists `claude/README.md`, `claude/settings.example.json`, `claude/statusline-command.sh` — so `symlink-setup.sh` will no longer `SKIP` them on a fresh clone.

---

## Task 8: Open the consolidation PR

- [ ] **Step 1: Contamination check — `main..HEAD` is only our commits**

Run:
```bash
git log --oneline main..HEAD
```
Expected: exactly the commits from Tasks 1–5 plus the spec commit — all authored by you, all on-topic. If anything unexpected appears, stop and investigate before pushing.

- [ ] **Step 2: Push the branch**

Run:
```bash
git push -u origin feature/claude-tmux-integration
```

- [ ] **Step 3: Open the PR**

Run:
```bash
gh pr create --base main --head feature/claude-tmux-integration \
  --title "Consolidate tmux + Claude Code integration" \
  --body "Lands the full tmux/Claude integration as one unit: public \`claude/\` config dir (README, statusline, reconciled settings template), \`bin/claude-tmux-state\` + test, the \`@claude_state\` tmux tab rewrite with truecolor, and design/plan docs.

Supersedes #3: reconciles the tiered state hooks with the auto-label hook from #4 (which #3 had dropped), and keeps machine-private settings (security flags, private plugins/marketplaces) out of the public template per \`claude/README.md\`.

Spec: \`docs/superpowers/specs/2026-06-04-claude-tmux-integration-consolidation-design.md\`"
```
Expected: prints the new PR URL.

---

## Task 9: Merge and clean up (after the PR is reviewed/approved)

> Gate: do this only once the user is happy with the PR.

- [ ] **Step 1: Merge the PR**

Run:
```bash
gh pr merge feature/claude-tmux-integration --squash --delete-branch
```

- [ ] **Step 2: Close PR #3 as superseded**

Run:
```bash
gh pr close 3 --comment "Superseded by the consolidation PR, which reconciles the tiered @claude_state hooks with the auto-label hook and lands the full claude/ config dir."
```

- [ ] **Step 3: Delete stale local branches**

Run:
```bash
git checkout main && git pull
git branch -D feature/tmux-worktree-notice feature/claude-tmux-autonotice-mixed
```
Expected: both deleted. (`feature/tmux-worktree-notice` is fully merged; `feature/claude-tmux-autonotice-mixed` is superseded. `claude-tmux-state` is deleted by `--delete-branch`/PR close; if a local copy remains, `git branch -D claude-tmux-state` and remove its worktree with `git worktree remove ../dotfiles-claude-state`.)

- [ ] **Step 4: Final sanity**

Run:
```bash
git branch -vv && git worktree list && gh pr list --state open
```
Expected: only `main` (and any intentionally-kept branches); no leftover consolidation/worktree-notice/mixed branches; PR #3 no longer open.

---

## Notes / Out of Scope

- **Issue #2** ("clear Claude 'done' state on tab focus") stays open — a known follow-up, not part of this work.
- **`CLAUDE.md`** is git-excluded in this repo — no `CLAUDE.md` edits in any commit. Feature docs live in `docs/` and `claude/README.md`.
- The `~/.claude/settings.json.bak` backup can be removed once you've confirmed the live session behaves correctly across a few prompts.
