# Prototype Skill — Design

**Date:** 2026-06-12
**Status:** Approved

## Goal

A personal Claude Code skill (`prototype`) that, given a UI feature brief,
generates 5+ visually distinct design variants in parallel, opens a local
gallery page for side-by-side comparison, and supports iteration rounds until
a winner is promoted into real project code. Inspired by the internal
"prototype" skill described by an Anthropic engineer (since productized as
Claude Design); no clean standalone equivalent exists in the skills ecosystem.

## Where It Lives

- **Source (tracked):** `claude/skills/prototype/SKILL.md` in this repo.
- **Deployed:** symlinked to `~/.claude/skills/prototype` by
  `symlink-setup.sh` — add `skills/prototype` to the existing
  `CLAUDE_SYMLINK_FILES` array and extend the section's `mkdir -p` to create
  `$HOME/.claude/skills`. The existing loop handles directory symlinks as-is.

## Invocation

- Explicit: `/prototype <brief>` or "prototype this", "show me options",
  "explore designs", "visual brainstorm".
- Proactive: suggested when the user describes a UI feature whose look is
  unsettled.

## Mode Detection

Inspect the project the session is running in:

| Signal | Mode | Variant format |
|---|---|---|
| `react-dom` in package.json | React web | Self-contained HTML loading React + Babel standalone from CDN; component authored as real inline JSX |
| `react-native` / Expo in package.json | React Native | Same, rendered via react-native-web from CDN; gallery flags it as an approximation of native |
| Anything else | Static | Plain self-contained HTML/CSS (+ minimal JS) |

Self-contained means no local imports and no dev server — every variant file
renders when opened directly in a browser. CDN access requires network; if
offline, fall back to static HTML mode and say so.

## Variant Generation

1. Distill the brief (from the user's request + project context) into a short
   shared problem statement: purpose, audience, content requirements,
   technical constraints.
2. Pick 5 named, deliberately divergent design directions suited to the brief
   (e.g. editorial magazine, brutally minimal, retro terminal, luxury
   refined, playful toy-like). More if the user asks for more.
3. Spawn one subagent per direction, all in parallel, in a single message.
   Parallel isolation is the point — sequential generation converges on one
   aesthetic. Each subagent:
   - MUST invoke the `frontend-design` skill before writing code (breadth
     comes from the direction assignment; per-variant quality comes from
     frontend-design).
   - Writes exactly one file: `variant-<n>-<direction-slug>.html`, fully
     self-contained, realistic content (no lorem ipsum), with an HTML comment
     header carrying direction name + one-line rationale.
4. If a subagent fails, proceed with the survivors and tell the user which
   direction is missing. Never block the round on one failed variant.

## Gallery

The main session (not a subagent) generates `index.html` in the round
directory:

- Grid of cards, one per variant: direction name, rationale, and the variant
  rendered in an iframe; click a card to open the variant full-screen in a
  new tab.
- Round navigation: all rounds listed, current round highlighted and
  non-clickable.
- Open it with `open index.html` (macOS).

**Output location:** `.prototypes/<feature-slug>/round-<N>/` in the project
root. Excluded from git via `.git/info/exclude` (never edits tracked
`.gitignore`); plain directory when not in a git repo.

## Iteration

The user reacts in chat; each reaction starts a new round directory. The
winner's design direction is locked from then on. Feedback is classified
first (added 2026-06-12 after live use):

- **Surgical** (exact, one correct outcome — "remove the # symbols"): no
  agents; the winning file(s) are copied into the new round and edited
  directly, avoiding regeneration drift. Multiple finalists may be kept and
  refined this way, with the gallery showing only them.
- **Directional** (ambiguous — "more whitespace"): variant 1 of the new
  round is the faithful winner-plus-feedback; remaining variants are
  distinct parallel-agent interpretations of the same feedback.
- **Mixed**: surgical parts apply to every variant identically; only the
  directional parts fan out.

Same gallery machinery either way; repeat until the user is happy.

## Promotion

When the user declares a final winner in a React project, translate that
variant's JSX into a real component in the project: proper file location,
project conventions, design tokens / styling system. This is ordinary
implementation work and exits the skill (normal workflows — TDD, review —
apply from there). In static mode, promotion means handing over the final
HTML/CSS or adapting it into the project's templating as requested.

## Enhancements (2026-06-12, approved after live demo)

Ten additions, grouped by stage. The gallery becomes a shared asset
(`claude/skills/prototype/assets/gallery-template.html`); each round writes a
`variants.js` data file (`const ROUND = {slug, round, rounds, note, knobs?,
variants:[{n, file, direction, rationale, themed}]}`) and copies the template
as its `index.html`. `rounds` lists ALL rounds (every existing round's
variants.js is updated when a new round starts); the gallery renders the full
round list with the current round highlighted. `themed` marks variants that
implement the dual-palette convention; the theme buttons are disabled with a
tooltip when none do.

**Gallery (template features):**
1. *Viewport toggles* — header buttons (390px / 768px / full) resizing all
   variant iframes at once.
2. *Feedback capture* — per-card pick toggle + notes field, persisted to
   localStorage, plus a "copy feedback" button that assembles a structured
   summary for pasting back into the session.
3. *A/B compare* — select exactly two cards → 50/50 split overlay; scroll
   sync best-effort (same-origin only; degrades gracefully under file://).

**Generation (SKILL.md conventions):**
4. *Light/dark first-class* — every variant ships both palettes via
   `:root[data-theme]` custom props; a boot script reads `?theme=` (falling
   back to `prefers-color-scheme`); the gallery's explicit dark/light buttons
   (active one highlighted, initialized from the OS preference) reload
   iframes and full-screen links with the param. Variants lacking support
   ignore the param — the buttons are disabled when no variant supports it.
5. *Design-token awareness (react-web)* — detect project tokens
   (tailwind config, `:root` custom props, theme files); when found, the
   last two of five variants are token-constrained ("in our design system"),
   the rest free.
6. *Real-content injection* — Step 0 accepts data sources (file paths, JSON,
   copy decks); their real values are embedded in the brief and binding on
   agents.
7. *Props/state knobs (react-web)* — rounds may declare `knobs` in
   variants.js; the gallery renders a shared controls strip and broadcasts
   `{type:'proto:props', props}` via postMessage; variants implement a
   message listener updating component state.

**Iteration & promotion (SKILL.md):**
8. *Remix feedback class* — third Step 6 mechanism: one agent receives two
   (or more) variant files plus a combination instruction.
9. *Screenshot archiving* — after each gallery build, if a browser tool is
   available, capture per-variant PNGs into `round-N/shots/` (serving the
   round dir over localhost when the browser cannot read file://). Skipped
   silently when no browser tool exists.
10. *Design decision record* — maintain `.prototypes/<slug>/DECISIONS.md`
    (directions offered, winner, feedback trail per round); at promotion,
    offer to copy it into the project's docs.

## Non-Goals

- No persistent "taste memory" across features (gstack-style). Rounds carry
  context within a feature; that is enough.
- No screenshot/image generation — variants are live code, not pictures.
- No dev-server integration; fidelity to project tokens happens at promotion.

## Verification

- Invoke the skill in a scratch directory with a sample brief (e.g. "pricing
  page for a CLI tool"); confirm 5 variant files + gallery are written, the
  gallery opens, and all iframes render.
- Run one iteration round and confirm round-2 is generated and linked.
- Repeat in a scratch React project (Vite + react-dom) to confirm mode
  detection and JSX-via-CDN rendering.
- `shellcheck symlink-setup.sh` and a re-run of the script to confirm the new
  symlink lands and existing links report `OK`.
