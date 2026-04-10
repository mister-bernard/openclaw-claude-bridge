# research — 3-teammate research + writing team

Create a team with 3 teammates in split-pane tmux mode. Arrange panes as horizontal bars (even-vertical layout).

Roles and strict file ownership:

- **researcher**: gathers sources via WebFetch, WebSearch, and any available research tools. Read-only on the repo. Writes raw notes to `research/notes/<topic>.md`.
- **fact-checker**: reads the researcher's notes and verifies every claim against its cited source. Flags weak or missing citations. Writes verdicts to `research/verified/<topic>.md`. Does not edit the researcher's notes.
- **writer**: drafts the final output using only claims the fact-checker has verified. Writes to `research/output/<topic>.md`. Does not browse the web directly.

Routing rule: I (the lead) take the topic from the user and assign it to researcher. When notes are ready, researcher messages fact-checker. When verdicts are ready, fact-checker messages writer. Writer messages me when the draft is ready for review.

Give each teammate a one-line hello so I can confirm they came up, then wait for my first topic.
