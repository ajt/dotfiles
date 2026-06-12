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

**Real content:** if the user references a data source (a file path, JSON, an
API response, a copy deck), READ it and embed the actual values in the brief.
Mark them binding in every agent prompt: "the following values are real
project data — use them exactly, do not invent data."

## Step 1: Detect mode

Read `package.json` in the project root (if present):

| Signal | Mode | Variant format |
|---|---|---|
| `react-native` or `expo` in dependencies | `react-native` | Self-contained HTML via esm.sh `react-native-web` (approximation — flag it in the gallery) |
| `react-dom` in dependencies | `react-web` | Self-contained HTML, CDN React + Babel standalone, real inline JSX |
| otherwise | `static` | Plain self-contained HTML/CSS (+ minimal vanilla JS) |

Check `react-native` BEFORE `react-dom` (RN projects often have both). CDN
modes need network; if offline, fall back to `static` and tell the user.

## Step 1.5: Detect design tokens (react-web only)

Look for the project's design tokens: `tailwind.config.{js,ts,cjs,mjs}`,
`:root { --* }` custom properties in the project's stylesheets, `theme.*` /
`tokens.*` files. If found, extract the brand palette and type choices, and
split the round: the LAST TWO variants get token-constrained prompts ("you
must use these colors/fonts — show what this looks like inside our design
system", tokens pasted in); the rest explore freely. Put which variants are
constrained in the gallery `note`. If nothing is found, all variants are
free — don't mention it.

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
7. THEME: ship BOTH palettes. Define colors as custom properties under
   `:root[data-theme="dark"]` and `:root[data-theme="light"]` (your direction
   decides what its light reading is — printed-paper, inverted, etc. — but it
   must be intentional, not auto-inverted). First script in <head>:
   <script>
   document.documentElement.dataset.theme =
     new URLSearchParams(location.search).get("theme") ||
     (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
   </script>
{8. KNOBS — include ONLY when the round declares knobs (react-web): the
   component's key inputs must be driven by state initialized to {defaults},
   updated by:
   window.addEventListener("message", (e) => {
     if (e.data && e.data.type === "proto:props") setProps(e.data.props);
   });}

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

The gallery is a shipped app: copy it from this skill's directory (the "Base
directory for this skill" announced when the skill loads):

```bash
cp "{skill-base-dir}/assets/gallery-template.html" "{round-dir}/index.html"
```

Then write `{round-dir}/variants.js` yourself (main session, not an agent):

```js
const ROUND = {
  slug: "{slug}",
  round: {N},
  prevRounds: [{existing earlier round numbers}],
  note: "{optional banner: RN approximation warning, token-constrained list, iteration context}",
  knobs: [ // OPTIONAL — react-web rounds where you defined knobs
    { key: "used", label: "API calls used", type: "number", default: 84211 }
    // types: "number" | "text" | "toggle"
  ],
  variants: [
    { n: 1, file: "variant-1-{direction-slug}.html",
      direction: "{direction-name}", rationale: "{agent's one line}" }
    // ...one per surviving variant
  ]
};
```

Omit `knobs` entirely when unused; omit `note` when there's nothing to say.
The gallery gives the user: viewport toggles (390/768/full), a light/dark
toggle (reloads variants with `?theme=`), a ★ pick + notes box per card with
a "copy feedback" button (they paste the result back to you — treat it as
Step 6 input), and an A/B compare overlay.

Then: `open "{round-dir}/index.html"` and summarize the directions for the
user in one line each. Mention that picks/notes in the gallery can be copied
back here with the "copy feedback" button.

## Step 5.5: Archive screenshots (best effort)

If a browser tool is available (e.g. Playwright MCP), capture each variant to
`{round-dir}/shots/variant-{n}.png` so rounds stay reviewable without
rendering and can be embedded in PRs/specs. Containerized browsers cannot
read host `file://` paths — serve the project dir first:

```bash
cd {project-root} && python3 -m http.server {port} &   # then browse
# container browsers reach the host at http://host.docker.internal:{port}
# kill the server when done
```

Containerized browser tools save screenshots INSIDE their container, not on
the host — find the container (`docker ps`), locate the files (often
`/home/node/`), and extract with
`docker cp <container>:/home/node/<shot>.png {round-dir}/shots/variant-<n>.png`.
Verify by content (`file *.png`), not by exit code.

If no browser tool exists, skip and tell the user in one line. Never block
the round on screenshots.

## Step 6: Iterate

When the user reacts, start `round-{N+1}`. The winner's design direction is
now LOCKED — rounds never reopen the aesthetic. First classify each piece of
feedback, because it determines the mechanism:

**Surgical feedback** — exact, deterministic, one correct outcome ("remove the
# symbols", "20px not 36px", "swap those two sections"). Do NOT fan out:
copy the winning file(s) into the new round and apply the edits yourself with
direct Edit calls. Regenerating from scratch risks drifting details the user
never mentioned. The user may also keep multiple finalists this way ("I like
1 and 4, tweak each") — the round then contains exactly those refined files
and the gallery shows only them.

**Directional feedback** — ambiguous, many plausible readings ("more
whitespace", "the CTA gets lost", "feels cramped"). The ambiguity is the
value, so fan out the INTERPRETATIONS:

- Variant 1 of the new round = the chosen winner with the feedback applied
  faithfully (the conservative reading). Its agent prompt includes the
  winner's full file content.
- The remaining variants are distinct readings of the same feedback (four
  different answers to what "more whitespace" could mean), each still a
  parallel agent with the winner's file content as context plus its own twist.

**Remix feedback** — combine named elements of multiple variants ("take 1's
typography with 4's layout"). One agent per remix, given ALL named variants'
full file contents and an explicit combination instruction (which element
comes from where, and which variant's character wins when they conflict).
A remix is one variant in the round; it composes freely with surgical and
directional variants in the same round.

**Mixed feedback** splits naturally: apply the surgical parts to every
variant identically; fan out only on the directional parts; spawn a remix
agent for each combination request.

Same gallery machinery either way; nav links to all prior rounds. Repeat
until happy.

## Step 6.5: Record decisions

Maintain `.prototypes/{slug}/DECISIONS.md` — append after every round:

```markdown
## Round {N} — {date}
**Offered:** {direction}: {rationale} (one line each)
**User picked:** {variants, or "none — feedback only"}
**Feedback:** {the user's reaction, verbatim or tightly paraphrased}
```

This file is the design provenance: why the winner won and what was
considered and rejected.

## Step 7: Promote

When the user declares a final winner:

- **React project:** translate the winning variant's JSX into a real component
  in the project — proper file location, naming, design tokens, and styling
  system per project conventions. This is ordinary implementation work: exit
  this skill and follow normal workflows (TDD, review).
- **Static mode:** hand over the final HTML/CSS or adapt it into the project's
  templating as the user requests.

At promotion, offer to copy `DECISIONS.md` into the project's docs (e.g.
`docs/design/{slug}-decisions.md`) alongside the component — the exploration
trail is the design justification. Offer to delete `.prototypes/{slug}/`
after promotion; don't delete it unprompted.
