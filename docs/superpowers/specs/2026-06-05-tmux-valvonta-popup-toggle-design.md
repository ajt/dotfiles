# Floating valvonta: toggle, per-project persistence, hidden banner — design

Date: 2026-06-05
Status: approved, pre-implementation
Branch: `fix/tmux-valvonta-popup-pane-path` (folded onto the same branch / PR #7 as the
`-d` fix this extends — the toggle replaces that fix's `bind v`)

## Problem

The `prefix v` floating valvonta popup works, but three behaviors are missing:

1. **Toggle.** `Ctrl-b v` only opens; closing needs valvonta's `q`. The user wants the same
   key to close it.
2. **Leave and return.** The user wants to navigate other tmux windows "while the float is
   open." tmux popups are **modal** — there is no non-modal floating pane, and you cannot
   see or switch windows while a popup is on screen. The realistic delivery is a toggle that
   *hides* the float (so you can navigate) and re-shows it.
3. **Hidden banner.** Start valvonta with the large "VALVONTA" header hidden.

### Constraints verified empirically (tmux 3.6a, this machine)

- `display-popup` is modal: prefix keys go to the popup, not the underlying session — so
  toggle-close and window-switching both require the popup to *be* a tmux client (a nested
  session), not a raw program.
- `#{m:vlv-*,#{session_name}}` distinguishes "inside the float" (`1`) from "elsewhere" (`0`).
- `if-shell -F` with `{ }` brace command blocks parses and stores correctly.
- **`$TMUX` is set inside a popup, yet `tmux new-session -A -s X 'cmd'` still works there**
  (create + attach succeeds, no "sessions should be nested" error) — so **no `env -u TMUX`
  is needed**.
- `new-session -A` on an existing session attaches without creating a duplicate.

## Decisions

- **Persistent per project** (user's choice): one background session per repo, hidden (not
  killed) on toggle-off, resuming instantly with preserved state. Keyed by the canonical
  main repo root, so all worktrees of a project share one instance.
- **Floax-style toggle:** `prefix v` = `if-shell` on session name → `detach-client` (hide)
  when inside a `vlv-*` session, else open the popup.
- **`--no-title`** hides the banner.
- **Close semantics:** `Ctrl-b v` hides (persists); valvonta's `q` quits (ends that
  project's session; next open is fresh).

## Design

### Toggle binding (`.tmux.conf`) — replaces the current `bind v`

```tmux
bind v if-shell -F '#{m:vlv-*,#{session_name}}' {
  detach-client
} {
  display-popup -E -b rounded -T ' valvonta ' -w 70% -h 40% \
    -d '#{pane_current_path}' "$HOME/bin/tmux-valvonta-popup"
}
```

- Inside the float (session name matches `vlv-*`) → `detach-client` hides it; the session
  and valvonta keep running.
- Anywhere else → open the popup (cwd set to the pane path via `-d`, the verified
  mechanism), running the launcher.

### Launcher (`bin/tmux-valvonta-popup`) — same checks, new final step

All existing guards stay (valvonta installed → git work tree → canonical main root → config
present, else the stay-open friendly hint). The only change is the success path: instead of
`exec valvonta --repo "$main_root"`, derive a stable per-repo session name and attach/create
it:

```sh
# Stable per-project session name from the canonical root (so every worktree of
# a repo shares one instance). slug is human-readable; cksum of the full path
# disambiguates same-named repos in different locations.
slug=$(printf '%s' "$repo_name" | tr -cs 'A-Za-z0-9_' '-' | sed 's/^-//; s/-$//')
hash=$(printf '%s' "$main_root" | cksum | cut -d' ' -f1)
session="vlv-${slug}-${hash}"

# -A attaches if the session exists (instant resume with preserved state), else
# creates it running valvonta with the banner hidden. Detaching (prefix v) hides
# it; `q` inside valvonta quits and ends the session. Verified: tmux new-session
# works inside a display-popup despite $TMUX being set, so no `env -u TMUX`.
exec tmux new-session -A -s "$session" "valvonta --no-title --repo \"$main_root\""
```

`repo_name` is the existing `basename "$main_root"`.

### Flow

1. `prefix v` in a normal window → popup opens in the pane's repo → launcher resolves the
   canonical root → attaches/creates `vlv-<slug>-<hash>` running `valvonta --no-title` →
   float shows.
2. `prefix v` inside the float → `detach-client` → popup closes, session persists.
3. `prefix v` again (same or another worktree window of that repo) → attaches the
   still-running session → instant resume.
4. `prefix v` in a different project's window → that project's own `vlv-*` session.
5. `q` inside valvonta → quits → session ends → next open is fresh.
6. No config / not a git repo / valvonta missing → the existing stay-open hint (raw popup;
   any key closes). The toggle-detach only applies once a `vlv-*` session exists.

## Files touched

| File | Change |
|---|---|
| `.tmux.conf` | replace `bind v` with the `if-shell` toggle |
| `bin/tmux-valvonta-popup` | session-name derivation + `exec tmux new-session …` (with `--no-title`) instead of `exec valvonta` |
| `tests/tmux-valvonta-popup.test.sh` | stub `tmux`; assert the launcher execs `tmux new-session -A -s vlv-… "valvonta --no-title --repo <root>"`; identical session name for the repo and a linked worktree of it |
| `tests/tmux-valvonta-binding.test.sh` | assert the toggle: `if-shell`, `detach-client`, and the open branch still passes the path via `-d` with no `#{…}` to the launcher |
| `docs/superpowers/specs/2026-06-05-tmux-valvonta-popup-toggle-design.md` | this spec |

## Testing

- **Launcher unit tests** (extend the existing hermetic harness): add a `tmux` stub that
  records its args, alongside the `valvonta` stub (now needed only so `command -v valvonta`
  passes — valvonta is no longer executed by the launcher, only named inside the session
  command). The locked-down `PATH` gains `cksum`, `tr`, `sed`, and the `tmux` stub. Assert:
  - configured repo → recorded `tmux` args are `new-session -A -s vlv-<slug>-<hash>
    valvonta --no-title --repo <root>`;
  - the session name is identical when launched from the repo root and from a linked
    worktree of it (per-project persistence);
  - hint paths unchanged (non-git, missing valvonta, no config) — `tmux` stub never invoked.
- **Binding test:** assert `if-shell`, `detach-client`, the `-d` open branch, and no `#{…}`
  handed to the launcher.
- **Live verification** (the interactive part that can only be proven by running): `prefix v`
  opens the float with the banner hidden; `prefix v` inside hides it and the `vlv-*` session
  survives (`tmux ls`); `prefix v` again resumes the same instance; a second project gets its
  own session; `q` ends the session.

## Tradeoffs / out of scope

- `vlv-*` sessions appear in `tmux ls` / the `prefix s` switcher. Accepted cost of
  persistence.
- Nested-client behavior while open (prefix keys act on the float's session). The distinct
  rounded ` valvonta ` border mitigates confusion.
- No simultaneous window navigation while the float is on screen — impossible with tmux
  popups; toggle off first.
- A per-project `valvonta.toml` is still required to show a dashboard (unchanged); otherwise
  the hint.
- The launcher is now intended to run *inside the popup*; its success path execs
  `tmux new-session`. Invoked directly from a normal shell it will create/attach a tmux
  session, and from inside a non-popup tmux pane it hits tmux's nesting guard. So manual
  checks should use the popup (or exercise the hint paths), not a bare `bin/tmux-valvonta-popup
  <dir>` call as before.
