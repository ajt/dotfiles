# Prototype Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A tracked personal Claude Code skill that generates 5+ divergent design variants via parallel subagents, opens a side-by-side browser gallery, and iterates rounds until a winner is promoted to real code.

**Architecture:** The skill is a single `SKILL.md` (instructions for the main session — no scripts, no binaries). It is tracked at `claude/skills/prototype/` in this repo and deployed by the existing `CLAUDE_SYMLINK_FILES` mechanism in `symlink-setup.sh`. Variants are always self-contained HTML files (CDN React + Babel in React projects) so the gallery never needs a dev server.

**Tech Stack:** Markdown skill file, bash (symlink script), self-contained HTML/JSX artifacts at runtime.

**Spec:** `docs/superpowers/specs/2026-06-12-prototype-skill-design.md`

---

### Task 1: Create the skill file

**Files:**
- Create: `claude/skills/prototype/SKILL.md`

There is no test framework for skill files; correctness is verified end-to-end in Tasks 4–5. This task is write + commit.

- [ ] **Step 1: Write `claude/skills/prototype/SKILL.md` with exactly this content**

````markdown
---
name: prototype
description: Use when the user wants to explore visual design options before committing to one — "prototype this", "show me options", "explore designs", "visual brainstorm" — or describes a UI feature whose look is unsettled. Generates 5+ deliberately divergent design variants via parallel subagents and opens a side-by-side gallery in the browser, then iterates rounds on the user's feedback.
---

# Prototype: Parallel Design-Variant Gallery

Generate genuinely different visual takes on one UI brief and show them side by
side in the browser before any production code gets written.

**Core principle: breadth through isolation.** Variants are produced by
parallel subagents that cannot see each other's work. NEVER generate variants
sequentially in one context — they converge on one aesthetic. All variant
agents go out in a single message.

## Step 0: Distill the brief

From the user's request and project context, write a short problem statement:

- Purpose and audience (what is this UI for, who uses it)
- Concrete content it must show — real names, numbers, copy. Never lorem ipsum.
- Technical constraints (dark mode? data density? touch?)

If you cannot name the real content (e.g. "a dashboard" — of what?), ask ONE
clarifying question before proceeding.

## Step 1: Detect mode

Read `package.json` in the project root (if present):

| Signal | Mode | Variant format |
|---|---|---|
| `react-native` or `expo` in dependencies | `react-native` | Self-contained HTML via esm.sh `react-native-web` (approximation — flag it in the gallery) |
| `react-dom` in dependencies | `react-web` | Self-contained HTML, CDN React + Babel standalone, real inline JSX |
| otherwise | `static` | Plain self-contained HTML/CSS (+ minimal vanilla JS) |

Check `react-native` BEFORE `react-dom` (RN projects often have both). CDN
modes need network; if offline, fall back to `static` and tell the user.

## Step 2: Set up the round directory

```bash
SLUG=<kebab-case-feature-slug>          # e.g. pricing-page
ROUND=1                                  # next integer if .prototypes/$SLUG exists
mkdir -p ".prototypes/$SLUG/round-$ROUND"
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null) && \
  { grep -qx '\.prototypes/' "$GIT_DIR/info/exclude" 2>/dev/null || \
    echo '.prototypes/' >> "$GIT_DIR/info/exclude"; }
```

Never add `.prototypes/` to a tracked `.gitignore` — `info/exclude` only.

## Step 3: Pick 5 divergent directions

Choose 5 NAMED design directions suited to the brief (more if the user asked).
They must be genuinely divergent — different typography, density, color
philosophy, and layout structure, not five tints of the same design. Draw from
tones like: editorial magazine, brutally minimal, retro terminal, luxury
refined, playful toy-like, industrial utilitarian, art deco geometric, organic
natural, maximalist chaos, soft pastel. Name each one and write a one-sentence
intent for it.

## Step 4: Spawn variant agents — parallel, single message

Dispatch one general-purpose subagent per direction, ALL in one message. Each
agent's prompt is built from this template (fill every `{...}`):

```text
You are generating ONE design variant. Your final text is data for the
orchestrator, not a user-facing message.

DIRECTION: "{direction-name}" — {one-sentence intent}. Commit to this
direction completely and push it further than feels safe. Intentionality over
intensity.

BRIEF: {problem statement from Step 0, including the real content}

MODE: {react-web | react-native | static}

REQUIREMENTS:
1. First invoke the `frontend-design` skill with the Skill tool and follow it.
   If that skill is unavailable, apply: distinctive non-default typography
   (pair a characterful display font with a refined body font), a committed
   color philosophy with one memorable accent, and meticulous spacing — no
   generic "AI slop" centered-card-with-drop-shadow defaults.
2. Write EXACTLY ONE file: {abs-round-dir}/variant-{n}-{direction-slug}.html
3. The file must be fully self-contained — no local imports, no dev server,
   renders when opened directly via file://. Skeleton for your mode is below.
4. Use the real content from the brief. Never lorem ipsum.
5. Line 1 of the file must be exactly:
   <!-- direction: {direction-name} | rationale: <one line, your words> -->
6. Make interactive states real where cheap (hover, focus, active tab).

Return exactly two lines: the file path, then the rationale line.
```

Mode skeletons to embed in the agent prompt:

`react-web`:

```html
<!-- direction: ... | rationale: ... -->
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://unpkg.com/react@18/umd/react.production.min.js"></script>
<script src="https://unpkg.com/react-dom@18/umd/react-dom.production.min.js"></script>
<script src="https://unpkg.com/@babel/standalone/babel.min.js"></script>
<style>/* all styles here */</style>
</head>
<body>
<div id="root"></div>
<script type="text/babel">
function Variant() { /* real JSX component, may use React.useState */ }
ReactDOM.createRoot(document.getElementById('root')).render(<Variant />);
</script>
</body>
</html>
```

`react-native`: same head, but the body script is
`<script type="text/babel" data-type="module">` importing from
`https://esm.sh/react-native-web` (`View`, `Text`, `StyleSheet`, ...) and
rendering with `ReactDOM.createRoot`. If an agent reports esm.sh problems,
have it fall back to a `static` variant that approximates RN layout
conventions and says so in its rationale.

`static`: plain HTML5 + `<style>` + optional small `<script>`. No frameworks.

If an agent fails or returns no file, proceed with the survivors and tell the
user which direction is missing. Never block a round on one failed variant.

## Step 5: Build and open the gallery

Write `{round-dir}/index.html` yourself (main session, not an agent) from this
template — one `.card` per variant, real direction names and rationales, and
one nav link per existing prior round:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>{slug} — round {N}</title>
<style>
  :root { color-scheme: dark; }
  body { margin:0; font-family:ui-monospace,'SF Mono',monospace; background:#111; color:#eee; }
  header { padding:16px 24px; display:flex; justify-content:space-between; align-items:baseline; border-bottom:1px solid #333; }
  header h1 { font-size:16px; margin:0; font-weight:600; }
  nav a { color:#7aa2f7; margin-left:12px; text-decoration:none; font-size:13px; }
  main { display:grid; grid-template-columns:repeat(auto-fit,minmax(480px,1fr)); gap:24px; padding:24px; }
  .card { border:1px solid #333; border-radius:8px; overflow:hidden; background:#1a1a1a; display:flex; flex-direction:column; }
  .card h2 { font-size:14px; margin:0; padding:12px 14px 4px; }
  .card p { font-size:12px; color:#999; margin:0; padding:0 14px 10px; }
  .card iframe { width:100%; height:520px; border:0; border-top:1px solid #333; background:#fff; }
  .card a { display:block; padding:9px 14px; font-size:12px; color:#7aa2f7; text-decoration:none; border-top:1px solid #333; }
  .note { padding:8px 24px; font-size:12px; color:#e0af68; border-bottom:1px solid #333; }
</style>
</head>
<body>
<header>
  <h1>{slug} — round {N}</h1>
  <nav><a href="../round-1/index.html">round 1</a></nav>
</header>
<!-- react-native mode only: -->
<div class="note">react-native-web approximation — verify on device before trusting pixels.</div>
<main>
  <div class="card">
    <h2>1 · {direction-name}</h2>
    <p>{rationale}</p>
    <iframe src="variant-1-{direction-slug}.html" loading="lazy"></iframe>
    <a href="variant-1-{direction-slug}.html" target="_blank">open full screen ↗</a>
  </div>
  <!-- ...one card per variant -->
</main>
</body>
</html>
```

Then: `open "{round-dir}/index.html"` and summarize the directions for the
user in one line each.

## Step 6: Iterate

When the user reacts ("variant 3, more whitespace, steal the nav from variant
1"), start `round-{N+1}`:

- Variant 1 of the new round = the chosen winner with the requested changes
  applied faithfully. Its agent prompt includes the winner's full file content.
- The remaining variants explore along the axis the user flagged (four
  different takes on "more whitespace"), each still a parallel agent with the
  winner's file content as context plus its own twist.
- Same gallery machinery; nav links to all prior rounds. Repeat until happy.

## Step 7: Promote

When the user declares a final winner:

- **React project:** translate the winning variant's JSX into a real component
  in the project — proper file location, naming, design tokens, and styling
  system per project conventions. This is ordinary implementation work: exit
  this skill and follow normal workflows (TDD, review).
- **Static mode:** hand over the final HTML/CSS or adapt it into the project's
  templating as the user requests.

Offer to delete `.prototypes/{slug}/` after promotion; don't delete it
unprompted.
````

- [ ] **Step 2: Commit**

```bash
git add claude/skills/prototype/SKILL.md
git commit -m "feat: add prototype skill — parallel design-variant gallery"
```

---

### Task 2: Wire the skill into symlink-setup.sh

**Files:**
- Modify: `symlink-setup.sh:95-99`

- [ ] **Step 1: Extend the mkdir and the symlink array**

Change line 95 from:

```bash
mkdir -p "$HOME/.claude"
```

to:

```bash
mkdir -p "$HOME/.claude/skills"
```

Change lines 97–99 from:

```bash
CLAUDE_SYMLINK_FILES=(
statusline-command.sh
)
```

to:

```bash
CLAUDE_SYMLINK_FILES=(
statusline-command.sh
skills/prototype
)
```

No other changes — the existing loop already handles directory symlinks
(`ln -s` of a directory) and prints `claude/skills/prototype` in its output.

- [ ] **Step 2: Lint**

Run: `shellcheck symlink-setup.sh`
Expected: no new warnings versus `git stash && shellcheck symlink-setup.sh; git stash pop` baseline (the script has pre-existing style warnings; the diff must add none).

- [ ] **Step 3: Run the script and verify by content, not exit code**

Run: `./symlink-setup.sh < /dev/null` then `readlink ~/.claude/skills/prototype`

Expected: script prints `LINK  /Users/ajt/.claude/skills/prototype → /Users/ajt/Projects/dotfiles/claude/skills/prototype`, existing entries print `OK`/`KEEP`, and readlink outputs `/Users/ajt/Projects/dotfiles/claude/skills/prototype`. The `< /dev/null` makes any unexpected overwrite prompt decline rather than hang; a declined prompt still exits 0, which is why the readlink check is the real verification.

- [ ] **Step 4: Commit**

```bash
git add symlink-setup.sh
git commit -m "feat: deploy claude/skills/prototype via symlink-setup"
```

---

### Task 3: Document the skill in claude/README.md

**Files:**
- Modify: `claude/README.md` (append a section; read the file first and match its existing tone/structure)

- [ ] **Step 1: Add a `skills/prototype` section**

Append (adjusting heading level to match the file):

```markdown
## skills/prototype

Personal skill: parallel design-variant gallery. Given a UI brief, spawns 5+
subagents (each on a divergent named design direction, each using the
frontend-design skill), writes self-contained HTML variants to
`.prototypes/<slug>/round-N/` in the target project, and opens an
`index.html` gallery for side-by-side comparison. Iterates rounds on
feedback; a final winner gets promoted to a real component. Deployed to
`~/.claude/skills/prototype` by `symlink-setup.sh`.
Spec: `docs/superpowers/specs/2026-06-12-prototype-skill-design.md`.
```

- [ ] **Step 2: Commit**

```bash
git add claude/README.md
git commit -m "docs: document the prototype skill in claude/README"
```

---

### Task 4: End-to-end verification — static mode

No code changes; this validates the skill text by executing it. Fix any defect found by editing `claude/skills/prototype/SKILL.md` (changes flow through the symlink) and commit the fix with `fix:`.

- [ ] **Step 1: Create a scratch project (not a git repo, no package.json)**

```bash
mkdir -p /tmp/proto-scratch-static && cd /tmp/proto-scratch-static
```

- [ ] **Step 2: Execute the skill against a sample brief**

Follow `~/.claude/skills/prototype/SKILL.md` exactly, as if the user said:
"prototype a pricing page for a CLI tool called shipit — three tiers: Free $0
(1 project), Pro $12/mo (unlimited projects, CI integration), Team $49/mo
(SSO, audit log); dark-mode developer audience."

- [ ] **Step 3: Verify outputs**

Run: `ls /tmp/proto-scratch-static/.prototypes/*/round-1/`
Expected: `index.html` plus 5 `variant-*.html` files.

Run: `head -1 /tmp/proto-scratch-static/.prototypes/*/round-1/variant-*.html`
Expected: every file starts with `<!-- direction: ... | rationale: ... -->`.

Open the gallery (`open .../round-1/index.html`) and confirm: 5 cards render in iframes, labels and rationales match, full-screen links work, no blank frames. Confirm the directions look genuinely divergent (different fonts/layout/color philosophy), not five tints of one design — if they converge, the agent prompts in SKILL.md Step 4 need strengthening; fix and re-run.

- [ ] **Step 4: Verify no git side effects in a non-repo**

Run: `ls /tmp/proto-scratch-static/.git 2>&1`
Expected: `No such file or directory` (the exclude step must no-op gracefully).

---

### Task 5: End-to-end verification — React mode and iteration

- [ ] **Step 1: Create a scratch React project (package.json only — CDN rendering needs no install)**

```bash
mkdir -p /tmp/proto-scratch-react && cd /tmp/proto-scratch-react && git init -q
printf '{"name":"scratch","dependencies":{"react":"^18.2.0","react-dom":"^18.2.0"}}\n' > package.json
```

- [ ] **Step 2: Execute the skill with a component brief**

Follow the skill as if the user said: "prototype a usage-meter card component
showing API calls used this month — 84,211 of 100,000, resets June 30, with
an upgrade CTA."

- [ ] **Step 3: Verify React mode engaged**

Run: `grep -l 'text/babel' /tmp/proto-scratch-react/.prototypes/*/round-1/variant-*.html | wc -l`
Expected: `5` — every variant is a JSX page, not plain HTML.

Run: `grep -c '^\.prototypes/$' /tmp/proto-scratch-react/.git/info/exclude`
Expected: `1`, and `git status --short` in the scratch repo shows nothing (only `package.json`, which is untracked but expected — confirm `.prototypes/` itself is absent from status output).

Open the gallery and confirm all 5 iframes render live React (interact with one stateful element).

- [ ] **Step 4: Run one iteration round**

As the user, reply: "variant 2, but tighter vertical spacing and a more
prominent CTA." Follow skill Step 6.

Expected: `.prototypes/<slug>/round-2/` with 5 new variants (variant 1 =
faithful winner + feedback), `round-2/index.html` linking back to round 1,
and the round-1 gallery still intact.

- [ ] **Step 5: Clean up scratch dirs**

```bash
rm -rf /tmp/proto-scratch-static /tmp/proto-scratch-react
```

---

### Task 6: Finish the branch

- [ ] **Step 1: Pre-PR contamination check**

Run: `git log --oneline main..HEAD`
Expected: ONLY this feature's commits (spec, skill, symlink, README, any `fix:` commits). If anything else appears, stop and investigate before pushing.

- [ ] **Step 2: Hand off**

Use superpowers:finishing-a-development-branch to choose merge/PR/cleanup.
