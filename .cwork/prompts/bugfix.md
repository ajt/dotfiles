Please fix GitHub issue #{{num}}: {{title}}
{{url}}
The branch {{branch}} is checked out in this worktree, which has its own isolated
database, Redis, Temporal namespace, and Django port. Read the issue first
(gh issue view {{num}}).

Work the bug methodically:
1. Reproduce it — write a failing test that demonstrates the bug before fixing.
2. Find the root cause; don't patch the symptom.
3. Fix it, and confirm the new test passes.
4. Run the full test suite and linters.

This worktree is based on dev. Open a PR against dev (not main) when green, using
conventional-commit messages. You can run the stack with make api / make
mobile-local; the port comes from this worktree's .env.local.

{{extra}}
