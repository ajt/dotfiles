# Prototype Skill Enhancements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (this plan is executed inline by the session that wrote it; the gallery template's full source lives in the implementation commit rather than duplicated here — the binding contracts are specified below).

**Goal:** Add the ten approved enhancements (spec: `docs/superpowers/specs/2026-06-12-prototype-skill-design.md`, "Enhancements" section) to the prototype skill.

**Architecture:** The gallery becomes a static single-file app shipped with the skill (`claude/skills/prototype/assets/gallery-template.html`). Each round writes `variants.js` (data) and copies the template as `index.html`. All dynamic behavior (viewport, theme, feedback, compare, knobs) is template JS reading that data. SKILL.md gains conventions that variant agents must follow (theme boot script, knobs listener) and new steps (tokens, screenshots, decision record, remix).

**Tech Stack:** Vanilla HTML/CSS/JS template, markdown skill instructions.

---

## Binding contracts

**variants.js** (written per round by the orchestrator):

```js
const ROUND = {
  slug: "pricing-page",
  round: 3,
  prevRounds: [1, 2],
  note: "optional banner text",
  knobs: [ // optional; react-web rounds only
    { key: "used", label: "API calls used", type: "number", default: 84211 }
  ],
  variants: [
    { n: 1, file: "variant-1-retro-terminal.html", direction: "retro-terminal", rationale: "one line" }
  ]
};
```

**Theme convention** (every variant, all modes): palettes under
`:root[data-theme="dark"]` and `:root[data-theme="light"]`; first script in
`<head>`:

```html
<script>
document.documentElement.dataset.theme =
  new URLSearchParams(location.search).get("theme") ||
  (matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
</script>
```

The gallery theme toggle reloads each iframe with `?theme=light|dark`.
Pre-convention variants ignore the param — that is the graceful path.

**Knobs protocol** (react-web variants in rounds that declare `knobs`):

```js
window.addEventListener("message", (e) => {
  if (e.data && e.data.type === "proto:props") setProps(e.data.props);
});
```

Gallery broadcasts to every iframe on input change. Variants without the
listener simply don't react.

**Feedback copy format** (assembled by the gallery's Copy Feedback button):

```
round 3 feedback (pricing-page):
picked: 1 (retro-terminal), 4 (industrial-utilitarian)
1 · retro-terminal: <card notes>
general: <general notes>
```

---

### Task 1: Gallery template asset

**Files:**
- Create: `claude/skills/prototype/assets/gallery-template.html`

- [ ] Single self-contained file, no external deps, dark chrome matching the current gallery aesthetic. Renders entirely from `ROUND` (script tag `<script src="variants.js">` before the app script). Features: viewport buttons (390 / 768 / full → iframe container widths), theme toggle (rewrites iframe `src` query param), per-card pick ★ + notes textarea (localStorage key `proto:<pathname>`), Copy Feedback button (clipboard, format above), compare checkboxes (exactly 2 → Compare button → overlay with two 50/50 iframes, best-effort scroll sync inside try/catch, Esc closes), knobs strip rendered only when `ROUND.knobs` exists (number/text/toggle inputs → postMessage broadcast), prev-round nav links, optional note banner.
- [ ] Commit: `feat: gallery template app for the prototype skill`

### Task 2: SKILL.md — gallery step rewrite + generation conventions

**Files:**
- Modify: `claude/skills/prototype/SKILL.md`

- [ ] Step 5 rewritten: write `variants.js` per the contract, then `cp "<skill-base-dir>/assets/gallery-template.html" "{round-dir}/index.html"`, then `open`. Remove the inline gallery HTML template.
- [ ] Step 4 agent-prompt template gains: the theme boot script + dual-palette requirement (all modes); the knobs listener requirement (react-web, only when the round declares knobs); when real content was injected in Step 0, "the following values are binding, do not invent data".
- [ ] New Step 1.5 "Detect design tokens" (react-web): look for `tailwind.config.*`, `:root` custom properties in the project's css, `theme.*` files; if found, variants 4–5 of the round get "constrained to these tokens" prompts (tokens pasted in), variants 1–3 stay free; gallery note says which are constrained.
- [ ] Step 0 gains "Real content": if the user references data (file, URL, JSON, copy deck), read it and embed the actual values in the brief.
- [ ] Commit: `feat: prototype skill — theme/knobs/tokens/content conventions`

### Task 3: SKILL.md — iteration & promotion steps

**Files:**
- Modify: `claude/skills/prototype/SKILL.md`

- [ ] Step 6 gains the third class **Remix** ("take 1's type with 4's layout"): one agent, all named variant files included, explicit combination instruction; composes with surgical/directional in the same round.
- [ ] New Step 5.5 "Archive screenshots": if a browser MCP is available, serve the round dir (`python3 -m http.server <port>`, container browsers reach it via `host.docker.internal`), screenshot each variant to `round-N/shots/variant-<n>.png`, kill the server. If no browser tool: skip, tell the user in one line.
- [ ] Step 7 (and each round): maintain `.prototypes/<slug>/DECISIONS.md` — per round: directions offered with rationales, what the user picked, the feedback verbatim; at promotion offer to copy it into the project's docs alongside the component.
- [ ] Commit: `feat: prototype skill — remix class, screenshot archive, decision record`

### Task 4: End-to-end verification (live demo dir)

- [ ] Build a `round-4` in `/tmp/shipit-demo` using the two round-3 light variants + the two round-2 dark finalists as a 4-card round with the NEW gallery (write variants.js, copy template). Verify in the container browser: viewport toggles resize, theme toggle reloads with `?theme=` (old variants unaffected — graceful), picks/notes persist across reload, Copy Feedback produces the format, compare overlay opens with 2 selections.
- [ ] Knobs + theme convention live test: scratch React project, ONE variant agent built to the new conventions (theme boot script + knobs listener), round with `knobs` declared; verify the gallery knob mutates the iframe and `?theme=light` flips it.
- [ ] Screenshot archiving: run Step 5.5 against round-4; confirm `shots/*.png` exist.
- [ ] DECISIONS.md: backfill `/tmp/shipit-demo/.prototypes/pricing-page/DECISIONS.md` from rounds 1–3 as the format example.
- [ ] Fix any defects in template/SKILL.md (changes flow through the symlink), commit as `fix:`.

### Task 5: Docs

- [ ] Update `claude/README.md` skills/prototype section: mention the assets/ template and the ten capabilities in one sentence each (compact list).
- [ ] Commit: `docs: README covers prototype skill enhancements`
