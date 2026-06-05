#!/usr/bin/env -S uv run --quiet
# /// script
# requires-python = ">=3.12"
# dependencies = ["litellm>=1.0", "langfuse>=2.0"]
# ///
"""Second-model reviewer for specs and plans.

Sends a spec or plan to a non-Claude model (Gemini) for an adversarial review
and writes the result next to the artifact. The first line of the model's
output is a machine-readable VERDICT token, so this acts as an approval gate,
not just advice.

    review.py --type spec --file path/to/foo.spec.md
    review.py --type plan --file path/to/foo.plan.md

Backend: Gemini direct via the Generative Language API. litellm reads the key
from the environment -- no proxy required. Langfuse tracing is optional and is
only wired up when its keys are present.

Env:
    GEMINI_API_KEY    required -- your Google AI Studio key (litellm reads it)
    REVIEW_MODEL      litellm model id (default: gemini/gemini-3.1-pro-preview)
    REVIEW_STATE_DIR  content-hash state dir (default: ~/.cache/claude-review)
    LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY  optional -- enable tracing
"""
import argparse, hashlib, os, pathlib, re, subprocess, sys, datetime
import litellm


def _hydrate_env_from_extra():
    """Pull review secrets from ~/.extra when they're not already in the env.

    Hooks inherit the environment of the `claude` process, which often lacks the
    vars set in ~/.extra -- e.g. when claude is started from cron / CI / a bare
    script rather than an interactive login shell that sourced it. If
    GEMINI_API_KEY isn't already set, source ~/.extra in a throwaway subshell and
    import the relevant keys, keeping ~/.extra the single source of truth."""
    if os.environ.get("GEMINI_API_KEY"):
        return
    extra = pathlib.Path.home() / ".extra"
    if not extra.is_file():
        return
    wanted = ["GEMINI_API_KEY", "REVIEW_MODEL",
              "LANGFUSE_PUBLIC_KEY", "LANGFUSE_SECRET_KEY", "LANGFUSE_HOST"]
    dump = 'printf "%s\\0" ' + " ".join(f'"${v}"' for v in wanted)
    for shell in ("zsh", "bash", "sh"):
        try:
            r = subprocess.run([shell, "-c", f'. "{extra}" >/dev/null 2>&1; {dump}'],
                               capture_output=True, text=True, timeout=10)
        except (FileNotFoundError, subprocess.SubprocessError):
            continue
        if r.returncode == 0 and "\0" in r.stdout:
            for name, val in zip(wanted, r.stdout.split("\0")):
                if val and not os.environ.get(name):
                    os.environ[name] = val
            return


_hydrate_env_from_extra()

# Optional tracing: only register Langfuse when its keys are present, so the
# reviewer runs on nothing but GEMINI_API_KEY without erroring on a missing key.
if os.environ.get("LANGFUSE_PUBLIC_KEY") and os.environ.get("LANGFUSE_SECRET_KEY"):
    litellm.success_callback = ["langfuse"]
    litellm.failure_callback = ["langfuse"]

MODEL = os.environ.get("REVIEW_MODEL", "gemini/gemini-3.1-pro-preview")
PROMPT_DIR = pathlib.Path(__file__).parent / "prompts"
STATE_DIR = pathlib.Path(os.environ.get(
    "REVIEW_STATE_DIR", pathlib.Path.home() / ".cache/claude-review"))


def load_prompt(kind: str) -> str:
    """Committed adversarial prompt, plus an optional git-ignored local overlay.

    A repo can extend the reviewer with private, project-specific guidance by
    dropping `prompts/<kind>.local.md` next to this script -- it's appended to
    the system prompt and never committed (see .gitignore)."""
    system = (PROMPT_DIR / f"{kind}.md").read_text()
    local = PROMPT_DIR / f"{kind}.local.md"
    if local.is_file():
        system += "\n\n" + local.read_text()
    return system


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--type", required=True, choices=["spec", "plan"])
    ap.add_argument("--file", required=True)
    ap.add_argument("--force", action="store_true",
                    help="re-review even if the content is unchanged")
    args = ap.parse_args()

    target = pathlib.Path(args.file).resolve()
    content = target.read_text(encoding="utf-8", errors="replace")
    h = hashlib.sha256(content.encode()).hexdigest()

    # Idempotency: don't re-burn a model call on byte-identical content.
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    seen = STATE_DIR / f"last-{args.type}-{target.name}"
    if not args.force and seen.exists() and seen.read_text().strip() == h:
        sys.exit(0)

    # No key (after the ~/.extra fallback) -> exit 3 so the Stop-hook can tell
    # "the gate couldn't run" apart from "Gemini errored" and offer to capture
    # the key. Distinct from the generic exit 1 below.
    if not os.environ.get("GEMINI_API_KEY"):
        print(f"[cross-review] {args.type} {target.name}: SKIPPED — no "
              f"GEMINI_API_KEY found (checked env and ~/.extra)", file=sys.stderr)
        sys.exit(3)

    system = load_prompt(args.type)
    kwargs = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user",
             "content": f"# Artifact under review: {target.name}\n\n{content}"},
        ],
        "metadata": {
            "trace_name": f"cross-review-{args.type}",
            "tags": ["cross-review", args.type],
        },
    }
    # Gemini 3+ deprecates temperature/top_p/top_k (sampling guidance is meant to
    # live in the system prompt); only pass temperature on models that still take it.
    if not re.search(r"gemini-([3-9]|\d{2,})", MODEL):
        kwargs["temperature"] = 0.2

    try:
        resp = litellm.completion(**kwargs)
    except Exception as e:
        # Fail open: write no review file, so the Stop-hook gate won't block. Emit
        # one clean line instead of a traceback for manual / commit-hook runs.
        detail = " ".join(str(e).split())
        detail = (detail[:300] + "…") if len(detail) > 300 else detail
        print(f"[cross-review] {args.type} {target.name}: SKIPPED — {MODEL} "
              f"call failed: {detail or type(e).__name__}", file=sys.stderr)
        sys.exit(1)
    review = (resp.choices[0].message.content or "").strip()

    m = re.match(r"VERDICT:\s*(APPROVE|CHANGES|BLOCK)\b", review)
    verdict = m.group(1) if m else "CHANGES"  # fail safe: if unparseable, make a human look

    out = target.with_suffix(target.suffix + ".review.md")
    stamp = datetime.datetime.now().isoformat(timespec="seconds")
    out.write_text(
        f"<!-- {MODEL} · {args.type} cross-review · {stamp} -->\n\n{review}\n",
        encoding="utf-8")
    seen.write_text(h)

    # One line to stdout so a hook/transcript shows the gate result at a glance.
    print(f"[cross-review] {args.type} {target.name}: {verdict} -> {out}")
    # Exit 0 always (never block a commit). To use as a hard gate in a PR check,
    # branch on the verdict token in the review file or have CI parse this line.


if __name__ == "__main__":
    main()
