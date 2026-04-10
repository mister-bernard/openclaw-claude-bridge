# full-stack — 4-teammate full-stack development team

Create a team with 4 teammates in split-pane tmux mode. Arrange panes as horizontal bars (even-vertical layout).

Roles with strict, non-overlapping file ownership (this is critical — Agent Teams has no file locking, so two teammates editing the same file silently clobber each other):

- **backend**: owns `src/server/`, `src/api/`, `migrations/`, `db/`. Writes endpoints, database schema, server logic. Does not touch frontend files.
- **frontend**: owns `src/client/`, `src/components/`, `public/`, `styles/`. Writes UI, client state, styling. Does not touch server files.
- **tests**: owns `tests/`, `spec/`, `e2e/`, `__tests__/`. Writes all test code. May read production code but may not edit it — instead, messages backend or frontend with requested changes.
- **ops**: owns `scripts/`, `Dockerfile*`, `compose.yml`, `.github/workflows/`, infrastructure configs. Does not touch application code.

Routing rule: I (the lead) take feature requests from the user and break them into subtasks via the shared task list. Each teammate claims tasks in their ownership area. Cross-cutting changes (e.g. an API contract change) go through me so I can coordinate and prevent conflicts.

Give each teammate a one-line hello identifying their role, then wait for the first feature request.
