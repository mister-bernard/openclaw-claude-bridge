# debug — 3-teammate root-cause + fix team

Create a team with 3 teammates in split-pane tmux mode. Arrange panes as horizontal bars (even-vertical layout).

Roles with strict responsibilities:

- **reproducer**: builds the smallest possible failing test case that exhibits the bug. Read-only on everything except `tests/repro/`. Once the repro is solid and reliably fails on main, messages the fixer.
- **fixer**: proposes and implements a fix once the reproducer is ready. Reads the repro, reads the affected code, writes the patch. Does not modify the repro test. Messages the verifier when ready.
- **verifier**: runs the repro against each proposed fix. Red = rejects the fix with specific output and sends it back to fixer. Green = approves and messages me (the lead).

Hard rule: no fix ships without a verifier sign-off. If fixer disagrees with a rejection, they escalate to me — they do not loop with the verifier indefinitely.

Give each teammate a one-line hello, then wait for my bug report.
