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
