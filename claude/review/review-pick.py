#!/usr/bin/env python3
"""review-pick -- sidecar TUI to triage a second-model (Gemini) review and emit
a hand-curated, TRUSTED handoff for Claude Code.

You are the trust boundary. The reviewer's free text is rendered for *you* in
the terminal; you multi-select the findings worth acting on; only your selection
is written out and copied to the clipboard. The raw critique never enters the
Claude session, so a poisoned spec can't steer it through the review channel.

Usage:
    review-pick                       # newest *.review.md in the repo
    review-pick specs/foo.spec.md     # the review beside this artifact
    review-pick foo.spec.md.review.md
    review-pick --json [target]       # structured findings as JSON, no TUI

--json powers the gate's autonomous handling protocol (see stop-review.py):
Claude runs it to get the findings as structured data, sanity-checks each
finding on its merits, applies the survivors to the artifact, and reports what
it applied and rejected. The TUI mode remains for hand-curated human triage.

Needs gum (TUI mode only):  brew install gum
"""
import json, os, re, shutil, subprocess, sys, pathlib

THEME = {
    "BLOCK":   {"glyph": "✗", "color": "196"},  # red    ✗
    "CHANGES": {"glyph": "⚠", "color": "214"},  # amber  ⚠
    "APPROVE": {"glyph": "✓", "color": "47"},   # green  ✓
    "UNKNOWN": {"glyph": "•", "color": "245"},  #        •
}
ACCENT = "51"    # cyan
DIM    = "243"

# ---- gum plumbing ----------------------------------------------------------
def need_gum():
    if not shutil.which("gum"):
        sys.exit("\n  review-pick needs gum:  brew install gum\n")

def gum(*args):
    subprocess.run(["gum", *args])

def gum_out(*args):
    r = subprocess.run(["gum", *args], capture_output=True, text=True)
    return r.returncode, r.stdout

def fmt_md(md):
    try:
        subprocess.run(["gum", "format"], input=md, text=True)
    except Exception:
        print(md)

def style(text, color, bold=False):
    args = ["style", "--foreground", color]
    if bold:
        args.append("--bold")
    gum(*args, "--", text)

# ---- locate the review -----------------------------------------------------
def find_review(arg):
    if arg:
        p = pathlib.Path(arg)
        cand = p if p.name.endswith(".review.md") else p.with_name(p.name + ".review.md")
        if not cand.is_file():
            sys.exit(f"\n  no review file at {cand}\n")
        return cand
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True)
    base = pathlib.Path(root.stdout.strip()) if root.returncode == 0 else pathlib.Path.cwd()
    reviews = sorted(base.rglob("*.review.md"),
                     key=lambda f: f.stat().st_mtime, reverse=True)
    if not reviews:
        sys.exit("\n  no *.review.md found -- run a review first\n")
    return reviews[0]

# ---- parse the review ------------------------------------------------------
SEC = re.compile(r"^##\s+(.*)$", re.M)
BULLET = re.compile(r"^\s*(?:[-*+]|\d+[.)])\s+(.*)$")
# A whole-line bold heading (e.g. "**Task 3: Add `show`**") — the reviewer uses
# these to group a finding's "what's wrong"/"the fix" bullets into one block.
BOLD_HEAD = re.compile(r"^\s*\*\*(.+?)\*\*[:.]?\s*$")
# Gemini sometimes drops the "VERDICT: " prefix and emits the bare token; accept
# both, but only near the top of the file so prose can't false-match.
VERDICT_RE = re.compile(
    r"^VERDICT:\s*(APPROVE|CHANGES|BLOCK)\b|^(APPROVE|CHANGES|BLOCK)\s*$", re.M)

def parse(text):
    text = re.sub(r"^\s*<!--.*?-->\s*", "", text, flags=re.S)
    vm = VERDICT_RE.search(text[:512])
    verdict = (vm.group(1) or vm.group(2)) if vm else "UNKNOWN"
    matches = list(SEC.finditer(text))
    sections = []
    for i, m in enumerate(matches):
        start = m.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        sections.append((m.group(1).strip(), text[start:end].strip()))
    if not sections:
        # format drift (no "## " sections): expose the whole critique minus the
        # verdict line as one pickable section instead of losing it.
        body = VERDICT_RE.sub("", text, count=1).strip()
        if body:
            sections = [("Findings", body)]
    return verdict, sections

def split_items(body):
    lines = body.splitlines()
    items, cur = [], None
    if any(BOLD_HEAD.match(l) for l in lines):
        # Block mode: a bold heading plus everything under it is ONE finding
        # (its bullets pair problem + fix — selecting them apart is meaningless).
        for l in lines:
            mh = BOLD_HEAD.match(l)
            if mh:
                if cur is not None:
                    items.append(cur)
                cur = mh.group(1).strip()
                continue
            mb = BULLET.match(l)
            frag = " ".join((mb.group(1) if mb else l).split())
            if not frag:
                continue
            if cur is None:
                cur = frag                       # stray text before the first heading
            else:
                cur += (" — " if mb else " ") + frag
        if cur is not None:
            items.append(cur)
    elif any(BULLET.match(l) for l in lines):
        for l in lines:
            mb = BULLET.match(l)
            if mb:
                if cur is not None:
                    items.append(cur.strip())
                cur = mb.group(1)
            elif cur is not None and l.strip():
                cur += " " + l.strip()
        if cur is not None:
            items.append(cur.strip())
    else:
        for para in re.split(r"\n\s*\n", body):
            p = " ".join(para.split())
            if p:
                items.append(p)
    # Drop placeholder bodies ("None.", "N/A") — a section with no findings
    # must not offer a pickable non-finding.
    return [i.strip() for i in items
            if i and i.strip() and i.strip().rstrip(".").lower() not in ("none", "n/a")]

def kind_of(title):
    t = title.lower()
    if "verdict" in t:
        return "verdict"
    if "good" in t:
        return "good"
    return "pick"

def truncate(s, n=110):
    s = " ".join(s.split())
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"

# ---- main ------------------------------------------------------------------
def main():
    argv = list(sys.argv[1:])
    as_json = "--json" in argv
    if as_json:
        argv.remove("--json")
    arg = argv[0] if argv else None
    review = find_review(arg)
    artifact_path = str(review)[: -len(".review.md")]
    verdict, sections = parse(review.read_text(encoding="utf-8", errors="replace"))

    if as_json:
        doc = {"verdict": verdict, "artifact": artifact_path,
               "review_file": str(review), "sections": []}
        for title, body in sections:
            kind = kind_of(title)
            sec = {"title": title, "kind": kind}
            if kind == "pick":
                sec["items"] = split_items(body)
            else:
                sec["body"] = " ".join(body.split())
            doc["sections"].append(sec)
        print(json.dumps(doc, indent=2))
        return

    need_gum()
    th = THEME.get(verdict, THEME["UNKNOWN"])

    print()
    style("  review-pick · second-model triage", ACCENT, bold=True)
    gum("style", "--border", "double", "--padding", "1 4", "--margin", "1 0",
        "--width", "46", "--align", "center",
        "--border-foreground", th["color"], "--foreground", th["color"], "--bold",
        "--", f"{th['glyph']}  {verdict}")
    style(f"  {artifact_path}", DIM)

    # context panels (verdict + what's good) -- rendered for the human only
    for title, body in sections:
        if kind_of(title) in ("verdict", "good") and body:
            style(f"\n  {title}", ACCENT, bold=True)
            fmt_md(body)

    # selectable finding sections
    selected = {}
    for title, body in sections:
        if kind_of(title) != "pick":
            continue
        items = split_items(body)
        if not items:
            continue
        labels = [f"{i + 1}. {truncate(it)}" for i, it in enumerate(items)]
        style(f"\n  ▸ {title}  ({len(items)})", th["color"], bold=True)
        code, out = gum_out(
            "choose", "--no-limit", "--height", "14",
            "--cursor", "❯ ",
            "--cursor-prefix", "○ ",
            "--unselected-prefix", "○ ",
            "--selected-prefix", "◉ ",
            "--header", "space toggles · enter confirms · esc skips section",
            "--", *labels)
        if code != 0 or not out.strip():
            continue
        chosen = []
        for cl in out.splitlines():
            cl = cl.strip()
            if not cl:
                continue
            try:
                idx = int(cl.split(".", 1)[0]) - 1
            except ValueError:
                continue
            if 0 <= idx < len(items):
                chosen.append(items[idx])
        if chosen:
            selected[title] = chosen

    if not selected:
        style("\n  nothing selected — nothing written.\n", DIM)
        return

    # optional human note (also trusted -- you wrote it)
    style("\n  add a note for Claude? (optional, ctrl-d / esc to skip)", ACCENT)
    _, note = gum_out("write", "--width", "82", "--height", "5",
                      "--placeholder", "e.g. skip #2, the spec is intentionally vague there…")
    note = note.strip()

    # assemble the curated handoff
    out = [f"# Review triage — hand-curated from the second-model review",
           f"Target artifact: `{artifact_path}`",
           "",
           "Apply the following selected findings to that artifact:",
           ""]
    for title, items in selected.items():
        out.append(f"## {title}")
        out += [f"- {it}" for it in items]
        out.append("")
    if note:
        out += ["## My note", note, ""]
    handoff = "\n".join(out).rstrip() + "\n"

    # .txt so the Stop hook's spec/plan matcher ignores it (it only scans *.md)
    out_path = pathlib.Path(artifact_path + ".selected.txt")
    out_path.write_text(handoff, encoding="utf-8")

    copied = ""
    if shutil.which("pbcopy"):
        subprocess.run(["pbcopy"], input=handoff, text=True)
        copied = "  ·  on your clipboard"

    n = sum(len(v) for v in selected.values())
    print()
    gum("style", "--border", "rounded", "--padding", "1 2", "--margin", "1 0",
        "--border-foreground", th["color"], "--foreground", "255",
        "--", f"✓  curated {n} finding(s)  →  {out_path.name}{copied}")
    style("  paste it into Claude, or:  \"apply the curated findings in " + out_path.name + "\"", ACCENT)
    style("  you selected this text, so it's trusted — the raw critique never touched the session\n", DIM)

if __name__ == "__main__":
    main()
