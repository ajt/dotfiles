Please work GitHub issue #{{num}}: {{title}}
{{url}}
The branch {{branch}} is already checked out in this worktree, which has its
own isolated database, Redis, Temporal namespace, and Django port. Read the full
issue first (gh issue view {{num}}), then implement a complete fix.
Conventions:

This worktree is based on dev. When the work is done and green, open a PR
against dev (not main).
Run the test suite and linters before opening the PR.
Use conventional-commit messages.
You can run the stack in this worktree with make api / make mobile-local;
the port comes from this worktree's .env.local, so it won't collide with
other sessions.

{{extra}}
