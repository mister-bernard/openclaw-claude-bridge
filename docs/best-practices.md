# Claude Code Best Practices for `cc` Users

*A field guide for engineers running Claude Code daily over mosh, with
Agent Teams and a synthesized `CLAUDE.md`. Assumes you already have `cc`
installed and working.*

---

## Table of Contents

1. [CLAUDE.md: What Belongs There and What Doesn't](#claudemd-what-belongs-there-and-what-doesnt)
2. [Auto-Memory: The Other Context Layer](#auto-memory-the-other-context-layer)
3. [Settings.json: Permission Tuning](#settingsjson-permission-tuning)
4. [Hooks: Genuine Patterns, Not Toy Examples](#hooks-genuine-patterns-not-toy-examples)
5. [Slash Commands and Skills](#slash-commands-and-skills)
6. [Agent Teams: When It Pays Off and When It Doesn't](#agent-teams-when-it-pays-off-and-when-it-doesnt)
7. [Plan Mode vs Normal Mode](#plan-mode-vs-normal-mode)
8. [Tmux + Mosh Ergonomics](#tmux--mosh-ergonomics)
9. [Context and Cost Management](#context-and-cost-management)
10. [Subagents: Delegate vs Do It Yourself](#subagents-delegate-vs-do-it-yourself)
11. [Background Tasks and Parallel Execution](#background-tasks-and-parallel-execution)
12. [Operational Habits That Compound](#operational-habits-that-compound)

---

## CLAUDE.md: What Belongs There and What Doesn't

`CLAUDE.md` is loaded at the start of every Claude Code session, before
any user message, and it persists across `/clear`. It is the closest
thing Claude Code has to a system prompt you actually control. The
bridge synthesizes it every 30 minutes from your OpenClaw workspace —
which means your source of truth is in `~/.openclaw/workspace/`, not in
`~/CLAUDE.md` directly.

**What earns its place in CLAUDE.md:**

- **Standing decisions that would otherwise require a repeated
  instruction.** If you've said "always use `trash`, never `rm`" twice
  in separate sessions, it belongs in `CLAUDE.md`. If you haven't
  needed to say it yet, it doesn't.
- **Identity and persona context.** Who the operator is, what the
  project is, what names and handles matter. Not biography — facts that
  affect action.
- **Hard security rules.** Things Claude should never do regardless of
  what a request says. Keep these crisp and unambiguous. The AGENTS.md
  section in the bridge is the right place; the synthesizer extracts
  the `# RULES` block automatically.
- **Tool and service reference.** Ports, health check URLs, restart
  commands, environment variable names. The kind of thing you'd
  otherwise look up in another terminal. The `## Key services` block
  from TOOLS.md is extracted for this purpose.
- **Operational rules with teeth.** Config gate procedures,
  backup-before-modify habits, gateway restart wrapper. Things where
  the cost of getting it wrong is real.

**What to leave out:**

- **Current task context.** Don't edit CLAUDE.md to give context for
  today's work. Put that in your first message or in a project-level
  CLAUDE.md (more on that below). The global one is for stable,
  cross-project truth.
- **Everything you're not prepared to maintain.** Stale instructions in
  CLAUDE.md are worse than no instructions — they create confident
  wrong behavior. If the "instructions" section has grown to 500 lines
  because you kept appending, trim it.
- **Aspirational rules.** "Always write tests" is noise unless you've
  wired a hook that enforces it. Claude will comply in the session
  where you ask and forget by the next one. Instructions without
  enforcement are wishes.
- **Architecture documentation.** Don't put your service graph in
  CLAUDE.md. It belongs in a project CLAUDE.md, or in a file Claude
  can read when it needs to.

**Project-level CLAUDE.md:**

Claude Code also reads a `CLAUDE.md` in the current working directory
(and walks up the directory tree). This is where project-specific rules
go — naming conventions, forbidden patterns, the test command, which
directories are generated. Keep it in the repo. It's the right scope
for things that are project-specific and should be versioned with the
code.

The hierarchy is: user-level `~/CLAUDE.md` → project-level
`./CLAUDE.md` → imported files. Project-level wins on conflicts (it's
closer to the work).

**What the synthesizer extracts:**

The bridge pulls specific sections from your workspace files:

- `IDENTITY.md`, `USER.md`, `SOUL.md` — full content, minus HTML
  comments
- `AGENTS.md` — the `# RULES` section through `# DELEGATION` (exclusive)
- `TOOLS.md` — `## Key services` through `## Pending` (exclusive)

If your workspace files use different section headers, edit
`~/.openclaw/bridge/lib/bridge.sh` — the awk ranges are on lines 103
and 114. It's a one-line change each.

**Sync timing:**

The cron job runs every 30 minutes. If you've made a workspace change
that's time-sensitive (new security rule, updated service port), run
`cc sync` manually. The synthesizer is fast — it's just awk and file
concatenation. There's no reason to wait for the cron.

---

## Auto-Memory: The Other Context Layer

Claude Code maintains a per-project memory directory at
`~/.claude/projects/<cwd-encoded>/memory/`. This is separate from
`CLAUDE.md` and operates differently.

**How it works:**

Auto-memory is populated by Claude Code during sessions when it decides
something is worth persisting. It writes small markdown files to the
memory directory. On subsequent sessions in the same project, Claude
reads those files as part of its startup context.

The key file is `MEMORY.md` in that directory. Claude Code both reads
and appends to it. Individual topic files (like `user_name.md`,
`feedback_testing.md`) are also loaded.

**What this means in practice:**

Auto-memory is complementary to CLAUDE.md, not a replacement. CLAUDE.md
is authoritative, human-maintained, and global. Auto-memory is Claude's
own notes — useful for session-to-session continuity on project-specific
discoveries, but unreliable as a source of truth. Claude may write
something incorrect to auto-memory and then confidently repeat it.

Treat auto-memory as a cache you can inspect and edit. If Claude keeps
doing something wrong and you can't figure out why, check
`~/.claude/projects/<cwd>/memory/MEMORY.md`. The wrong assumption is
probably sitting there.

**Practical interaction pattern:**

When you want Claude to remember something specifically for this
project — not globally, just here — tell it explicitly: "remember that
this project's test command is `pytest -x -q` — save it to memory."
Claude will write it to the project memory directory. On the next
session in the same working directory, it'll read it back.

For global facts, edit your workspace files and run `cc sync`. Don't
try to persist global context through the auto-memory system — it's
project-scoped and will be different in every cwd.

**The cwd encoding:**

The project directory under `~/.claude/projects/` is the working
directory with slashes replaced by dashes (plus surrounding dashes).
For example, cwd `/home/openclaw` becomes `-home-openclaw`. This is how
Claude Code separates memory across projects. If you always run from
the same directory, you have one memory context. If you `cd` to
different projects, each gets its own.

The cc wrapper sets `WORKDIR` to `$HOME` by default (overridable with
`CC_WORKDIR`). If you want project-specific memory to apply correctly,
make sure the lead session starts from the right directory, or set
`CC_WORKDIR` to the project root.

---

## Settings.json: Permission Tuning

`~/.claude/settings.json` is the machine-readable config Claude Code
reads at startup. The installer writes a copy from
`config/settings.json` in the repo. The live version is at
`~/.claude/settings.json`.

**The permission model:**

Claude Code has several modes. The three worth knowing:

- **`default`** — Claude asks permission before running any tool that
  modifies the system (writes, shell commands). Safe but interruptive
  on a dev machine where you trust the environment.
- **`acceptEdits`** — File writes are pre-approved; shell commands
  still require confirmation unless they match an `allow` rule. A
  reasonable middle ground if you're worried about Claude running
  arbitrary shell commands but not about file edits.
- **`bypassPermissions`** — All tools run without confirmation,
  including commands that would otherwise match a `deny` rule. Correct
  for a trusted dev VPS where you're the only user and you're
  supervising the session, *if* you understand that your deny list
  stops being enforced.

Set `defaultMode` under `permissions`:

```json
{
  "permissions": {
    "defaultMode": "acceptEdits"
  }
}
```

**Recommendation:** Start with `acceptEdits` plus a carefully curated
`allow` list of the shell commands you actually use. This gets you the
"no prompts" feel for edits and for whitelisted bash, while keeping
`deny` rules enforced as a real safety net. Reach for
`bypassPermissions` only when you want to explicitly opt out of all
checks (a disposable VM, a sandbox, an ephemeral experiment) — not as
the default on a machine you care about.

**The allow/deny/ask lists:**

`allow`, `deny`, and `ask` are arrays of permission strings. The format
is `ToolName(pattern)`.

Examples from the bridge's config:

```json
"allow": [
  "Bash(find:*)",
  "Bash(git:*)",
  "Bash(curl:127.0.0.1*)",
  "Read(*)",
  "Write(~/.openclaw/workspace/*)"
],
"deny": [
  "Bash(rm -rf /*)",
  "Bash(openclaw doctor --fix*)",
  "Write(~/.openclaw/openclaw.json)"
]
```

**Key patterns:**

- `Bash(git:*)` — any git command. More permissive than you might want
  if you don't want Claude pushing or force-resetting. Consider
  splitting into `Bash(git status)`, `Bash(git diff:*)`,
  `Bash(git log:*)` for read-only git while keeping `git push`, `git
  reset --hard` on the ask list.
- `Bash(curl:127.0.0.1*)` — curl to loopback only. Prevents Claude from
  making outbound HTTP calls via curl while still allowing health
  checks against local services.
- `Write(~/.openclaw/openclaw.json)` in deny — hard-blocks writes to a
  file that has caused repeated outages when written incorrectly.

**Deny takes priority over allow** — under the normal, `acceptEdits`,
and `default` modes. If a pattern matches both, the deny wins. Use this
to carve out exceptions: allow `Bash(*)` broadly but deny specific
dangerous commands. `bypassPermissions` ignores deny rules entirely,
which is the trap it sets.

**The `env` block:**

The settings file also has an `env` block for environment variables
injected into every Claude Code session:

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "0"
  }
}
```

`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is what enables the
lead+teammates model. Without it, Claude Code can still spawn
subagents, but not the persistent Agent Teams coordination layer.
`CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=0` leaves telemetry on — set
to `1` to disable it on air-gapped or privacy-sensitive machines.

**Project-level settings:**

You can also put a `settings.json` in `.claude/settings.json` inside a
project directory. Project settings merge with user-level settings,
with project settings taking precedence. This is the right place for
project-specific allows/denies (e.g., allowing `Bash(docker:*)` only in
projects that need it). Add `.claude/settings.local.json` (gitignored)
for personal overrides that shouldn't be committed.

---

## Hooks: Genuine Patterns, Not Toy Examples

Hooks run shell commands in response to Claude Code events. They're
configured in `settings.json` under a `hooks` key. The hook system is
the right tool when you want something to happen *consistently* — not
when Claude remembers, but every single time.

**The hook contract (read this first):**

Hooks receive a JSON payload on **stdin**, not as environment
variables. For a `Write|Edit` matcher on `PostToolUse`, the payload
looks roughly like:

```json
{
  "session_id": "abc123",
  "tool_name": "Edit",
  "tool_input": { "file_path": "/path/to/file.ts", "old_string": "...", "new_string": "..." },
  "tool_response": { "filePath": "/path/to/file.ts", "success": true }
}
```

Your hook command reads stdin, extracts what it needs (`jq` is the
standard tool), and does its thing. A hook exiting non-zero on
`PreToolUse` blocks the operation. On `PostToolUse` it logs a warning
but can't un-do the tool call.

**The hook events worth knowing:**

- **`PreToolUse`** — runs before a tool executes. Can block the tool
  by exiting non-zero.
- **`PostToolUse`** — runs after a successful tool call. Good for
  formatters, linters, auto-commits.
- **`Stop`** — runs when Claude is about to stop. Can force Claude to
  continue by exiting non-zero.
- **`Notification`** — runs on notification events (permission prompts,
  idle state). Good for alerting.
- **`PreCompact`** / **`PostCompact`** — runs around context
  compaction. Useful for snapshotting state before it gets summarized
  away.
- **`SessionStart`** — runs when a session begins. Good for loading
  per-session context that isn't appropriate for CLAUDE.md.

**Pattern 1: Auto-format on every file write (PostToolUse)**

If your project uses prettier, ruff, or gofmt, wire it as a
`PostToolUse` hook so Claude never leaves files unformatted:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_response.filePath // .tool_input.file_path' | { read -r f; [[ \"$f\" == *.ts || \"$f\" == *.tsx || \"$f\" == *.js ]] && npx --no-install prettier --write \"$f\"; } 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

The key insight: Claude will often write correct but unformatted code,
then in the next step notice it's not formatted and fix it — burning
two tool calls. A `PostToolUse` hook eliminates the second call
entirely. The file is formatted before Claude even sees the result.

**Pattern 2: Block writes to specific files (PreToolUse)**

Hard-block writes to files that have caused problems when Claude
edited them:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "jq -e '.tool_input.file_path | test(\"openclaw\\\\.json|/\\\\.env$|credentials\")' >/dev/null && { echo 'protected file — blocked by hook' >&2; exit 1; } || exit 0"
          }
        ]
      }
    ]
  }
}
```

Exit 1 blocks the operation. Claude sees the non-zero exit and reports
that the operation was blocked. This is stricter than a `deny` rule
because it can't be loosened accidentally by someone editing the allow
list.

**Pattern 3: Notify on idle (Notification)**

Over mosh from a laptop, you often step away while Claude works. A
`Notification` hook tells you when Claude is waiting:

```json
{
  "hooks": {
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.message // empty' | xargs -I{} notify-send 'Claude Code' {} 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

On a remote VPS where `notify-send` won't do anything useful, replace
the command with a POST to a Telegram bot, an SMS via Telnyx, or a
ping to a local HTTP listener on your laptop — anything that crosses
the wire.

**Pattern 4: Git checkpoint after significant edits (PostToolUse)**

Auto-commit after Claude writes files, creating a breadcrumb trail you
can roll back to:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "jq -r '.tool_response.filePath // .tool_input.file_path' | { read -r f; d=$(dirname \"$f\"); cd \"$d\" 2>/dev/null && git rev-parse --is-inside-work-tree >/dev/null 2>&1 && git add -A && git diff --cached --quiet || git commit -m 'auto: claude checkpoint' --quiet; } 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

This only commits if there are changes and fails silently if the file
isn't inside a git repo. The result is a granular git history you can
`git log --oneline` through to find the last working state. Use
sparingly — on a noisy refactor this can produce hundreds of commits.

**Pattern 5: Snapshot before compact (PreCompact)**

Compact is lossy. If you want a record of what was in context before
it got summarized, dump the transcript first:

```json
{
  "hooks": {
    "PreCompact": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "jq -c '.' >> ~/.claude/precompact-log.jsonl 2>/dev/null || true"
          }
        ]
      }
    ]
  }
}
```

Later you can grep the log to see what was in flight when auto-compact
fired. Useful when a session has gone sideways post-compact and you
need to reconstruct what decisions were made.

**What hooks are not good for:**

- **Complex logic.** If your hook script is more than a few lines, it's
  probably doing something that should be a skill or subagent instead.
  Hooks are fast, synchronous, and dumb.
- **Things that need Claude's reasoning.** Hooks run blind — they don't
  have Claude's context about what it's doing or why. They only see
  the tool call and its result.
- **Slow operations.** A `PostToolUse` hook that runs a 30-second
  type-check on every file write will make Claude Code feel broken.
  Run heavy checks only on narrow matchers (not `*`), or run them
  async and write results to a file Claude can check later.

**Testing hooks before shipping them:**

A hook that silently fails is worse than no hook — Claude's behavior
won't change, and you won't know why. Test the raw command by piping a
synthesized payload to it before wiring it in:

```bash
echo '{"tool_name":"Edit","tool_input":{"file_path":"/tmp/test.ts"},"tool_response":{"filePath":"/tmp/test.ts"}}' | <your-hook-command>
```

Check exit code *and* side effect. Only once that works should you
wrap the command with `2>/dev/null || true` and add it to settings.

---

## Slash Commands and Skills

Slash commands (`/foo`) and skills (`.claude/skills/foo/SKILL.md`) are
two layers of the same idea: packaged instructions Claude can invoke
on demand. The distinction matters.

**Slash commands:**

A slash command is a markdown file in `.claude/commands/`
(project-level) or `~/.claude/commands/` (user-level). When you type
`/foo`, Claude reads the file and follows its instructions.

Structure:

```
.claude/commands/foo.md
```

The file is a markdown prompt. Arguments from the command line are
available as `$ARGUMENTS`. Dynamic context can be injected with
backtick syntax — a command prefixed with `!` inside backticks runs at
load time and its stdout is injected into the prompt:

````markdown
---
allowed-tools: Bash(git log:*), Bash(git diff:*)
description: Show what changed since last tag
---

## Current state

- Last tag: !`git describe --tags --abbrev=0`
- Changes since then: !`git log $(git describe --tags --abbrev=0)..HEAD --oneline`

Summarize these changes as user-facing release notes. Group by type.
Highlight breaking changes.
````

The `!` command-injection syntax is how you give a slash command live
context without requiring Claude to go fetch it. Check your Claude
Code version's docs for the exact syntax before you commit to a
pattern — this area is under active development.

**When to create a slash command:**

- You type the same multi-step instruction more than twice a week.
- You want to enforce a specific output structure (release notes
  format, PR description template).
- You have a workflow with specific tool restrictions (e.g., a review
  command that should only read, never write).

**Skills:**

Skills are more structured: a `SKILL.md` file with YAML frontmatter
plus optional supporting files (scripts, templates, examples).

```
.claude/skills/create-migration/
├── SKILL.md
└── scripts/validate-migration.sh
```

```yaml
---
name: create-migration
description: Create a database migration. Use when adding or modifying a table.
allowed-tools: Read, Write, Bash
---

Create migration for: $ARGUMENTS

1. Generate a file in `migrations/` with timestamp prefix
2. Include up() and down() functions
3. Run `bash .claude/skills/create-migration/scripts/validate-migration.sh`
4. Report any errors
```

The `description` field is what Claude reads to decide whether to
invoke the skill automatically. Write it as a trigger: "Use when X."
If it's vague, Claude will either invoke it at the wrong time or never.

**The built-in slash commands worth knowing:**

- `/clear` — clears context. Does not reset settings or hooks.
- `/compact` — summarizes the current conversation and replaces it
  with the summary. Preserves session state, reduces token count.
- `/cost` — shows token usage for the current session.
- `/model` — switch model mid-session.
- `/permissions` — show the current permission state.
- `/hooks` — view and edit the active hooks for this project.

---

## Agent Teams: When It Pays Off and When It Doesn't

Agent Teams is `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. The cc wrapper
enables it via `settings.json`. What you get: the lead Claude can spawn
teammate instances in new tmux panes, each with its own context
window. The lead coordinates via a `SendMessage` tool. You always talk
to the lead.

**When it actually pays off:**

The break-even for Agent Teams is when the task is genuinely
decomposable into workstreams that don't need to read each other's
in-progress output. The canonical examples from the presets:

- **full-stack**: backend owns `src/server/`, frontend owns
  `src/client/`, tests own `tests/`, ops owns `scripts/`. These four
  teammates can work in parallel on a feature without stepping on each
  other — IF the API contract is stable. If the API is changing, the
  lead needs to serialize.
- **debug**: reproducer → fixer → verifier is a pipeline, not parallel
  work. You get the benefit of clean role separation (each agent is
  sharply focused), not parallelism. This is still valuable — the
  reproducer doesn't contaminate their context with fix attempts.
- **research**: researcher → fact-checker → writer is again a pipeline,
  with the benefit that each stage only reads from the previous
  stage's output, which keeps context clean.

**When it doesn't pay off:**

- **Tasks where files interact.** If backend and frontend are editing
  the same interface definition, they will clobber each other. Agent
  Teams has no file locking. The file ownership model in the presets
  is the only protection. Enforce it.
- **Short tasks.** Spawning teammates takes time and burns tokens on
  coordination. If you can finish in one session with one agent, do
  that.
- **Tasks requiring tight feedback loops.** If you need to see a
  result, react to it, and immediately course-correct, a team gets in
  the way. You have to talk to the lead, who relays to the teammate,
  who responds back. For tight iteration, solo is faster.
- **Teams of more than 5.** The docs suggest 3–5 as the sweet spot and
  field experience matches this. Beyond 5, coordination overhead
  dominates and you spend more tokens on `SendMessage` calls than on
  actual work. Start with 3, scale to 4 only if the workstreams are
  genuinely independent.

**Structuring the spawn prompt:**

The presets in `~/.openclaw/bridge/presets/` are worth studying as
templates. The key components of a good spawn prompt:

1. **Number and layout.** "Create a team with 4 teammates in
   split-pane tmux mode. Arrange as horizontal bars."
2. **Role + file ownership.** Be specific. "backend: owns
   `src/server/`, `src/api/`, `migrations/`. Does not touch frontend
   files." The "does not touch" constraint is as important as the
   ownership.
3. **Routing rule.** Tell the lead how to route. "Cross-cutting changes
   go through me so I can coordinate." This prevents teammates from
   messaging each other directly in ways that bypass the lead's
   visibility.
4. **Hello check.** "Give each teammate a one-line hello so I can
   confirm they came up." This is a cheap way to verify all panes
   initialized correctly before you start real work.

**The coordination trap:**

The most common failure mode: you ask the lead to do something that
requires teammate coordination, the lead sends messages, teammates
start working, and then they hit a dependency they didn't expect. Now
the lead is managing back-and-forth messages between teammates, and
you're watching tokens burn while waiting.

Prevent this by front-loading coordination: before spawning the team,
have the lead sketch the full plan, identify cross-cutting
dependencies, and resolve interface contracts (API shapes, shared
types, file formats). Only then spawn teammates. The upfront planning
session costs tokens but saves them on coordination thrash.

**Monitoring the panes:**

`cc` sets pane titles via `select-pane -T`. Use `Ctrl-b B` (horizontal
bars) to see all panes at once. The status bar at the top of each
pane shows the pane index and title. Watch the active pane indicator
in the border to see where work is happening.

If a teammate pane goes silent for more than a few minutes, it may be
stuck waiting for a tool permission or hit a rate limit. Check it with
`Alt+Arrow` to focus that pane, then scroll up with the mouse wheel to
see the last output.

---

## Plan Mode vs Normal Mode

Plan mode puts Claude into a read-only planning phase where it can
explore the codebase and produce a plan but cannot make changes.
Normal mode allows tool calls that modify state.

**Use plan mode when:**

- You're starting a substantial task and want to see Claude's approach
  before it touches anything. A plan takes a few seconds and costs far
  fewer tokens than a wrong implementation you have to undo.
- You're handing off a task to a teammate and want to review the
  approach first.
- You're debugging a complex issue and want a diagnosis before any
  fixes are applied.
- The task involves irreversible operations (schema migrations, API
  calls to external services, file moves).

**Use normal mode when:**

- The task is small and low-risk. Adding a helper function doesn't
  need a plan.
- You've already reviewed the plan and said "go."
- You're doing exploratory work and want to see results quickly. A
  wrong first attempt is useful feedback.

**Plan mode is not a safety mechanism.** If you approve the plan and
say "go," Claude switches to normal mode and executes. The plan is
only as good as your review of it. Read it. Ask "what's the failure
mode here" about each step that touches state you care about.

**The practical pattern:**

For anything larger than a single function: start in plan mode, read
the plan, push back on anything that looks wrong ("don't touch the
migration files, create a new one instead"), then say "proceed." For
small tasks: skip the plan, watch the tool calls in real time, stop
Claude and redirect if something goes sideways.

---

## Tmux + Mosh Ergonomics

This section is specific to the cc workflow: remote VPS, mosh
connection, isolated `cc` tmux socket.

**The fundamental mosh/tmux split:**

Mosh has no scrollback. It redraws the screen from its own state and
doesn't know about terminal history. When you scroll in a mosh session
without tmux, you're scrolling your local terminal emulator's buffer
of the mosh screen — and mosh's screen is only as tall as your current
window. Any output that scrolled off is gone.

Tmux is the scrollback. The `cc` config sets `history-limit 100000` —
100k lines per pane. That's the buffer you're scrolling through when
you use the mouse wheel or `Shift+PageUp` inside a cc session.

**Mouse wheel behavior:**

The tmux config binds `WheelUpPane` to auto-enter copy mode if the
pane isn't already in it. This means: scroll up with the mouse wheel →
you enter copy mode → you scroll through history. Scroll back down to
the bottom → the `-e` flag on `copy-mode` auto-exits copy mode → you're
back in the live pane.

If the mouse wheel isn't working in a Claude Code pane, check:

1. You're attached via `cc`, not via your personal tmux socket (`tmux
   -L cc ls` vs `tmux ls`).
2. The cc tmux config is loaded (run `cc status` to check the session
   is on the `cc` socket).
3. The Claude Code TUI hasn't captured mouse input itself — some
   Claude Code versions handle mouse differently inside the TUI.

**Keyboard scrollback:**

`Shift+PageUp` / `Shift+PageDown` is bound at the tmux level and works
everywhere, including when Claude Code's TUI would otherwise capture
mouse events. This is the most reliable scrollback method.

Inside copy mode (entered via mouse wheel or `Shift+PageUp`),
navigation is vi-style: `hjkl`, `/` to search, `v` to start selection,
`y` to yank.

**Detach/reattach:**

`Ctrl-b d` detaches. The session keeps running — Claude Code is still
executing whatever it was doing. `cc` (no arguments) reattaches. If
you're on a flaky mosh connection and get disconnected, just reconnect
mosh and run `cc` again.

This is the correct model for long-running tasks: start them, detach,
come back when they're done. Claude Code will have run the full task
in the background. Check the pane for output.

**Zero ESC lag:**

The config sets `escape-time 0`. Without this, tmux waits 500ms after
seeing `Escape` before sending it, to distinguish `Escape` from
`Escape + char` (which is how alt-keys are encoded). Mosh amplifies
any delay because it's already adding latency. `escape-time 0` means
vim mode-switching and any other ESC-heavy operation works without a
lag that makes you feel like the session is broken.

**Layout shortcuts:**

- `Ctrl-b B` — even-vertical (horizontal bars stacked top-to-bottom).
  Best for 3-4 pane teams — each gets a full-width strip.
- `Ctrl-b H` — even-horizontal (vertical columns side-by-side). Better
  for 2 panes on a wide terminal.
- `Ctrl-b T` — tiled. Automatic grid for any number of panes.

After spawning teammates, hit `Ctrl-b B` to reflow immediately. The
Agent Teams spawner creates panes but doesn't always lay them out
cleanly.

**Alt+Arrow pane navigation:**

`Alt+Arrow` (no prefix needed) jumps between panes. This works even
inside Claude Code's TUI. Use it to switch to a teammate pane, read
its output, then jump back to the lead.

**True color:**

The config sets `default-terminal "tmux-256color"` and the `Tc`
terminal override for true color. Claude Code's TUI uses 24-bit color
for syntax highlighting and status indicators. Without true color, you
get a degraded palette that makes the UI harder to read. If your SSH
or mosh connection strips true color, set `TERM=xterm-256color` on the
remote side and confirm the override is loading (`tmux info | grep
Tc`).

**Copy-paste over mosh:**

OSC 52 clipboard integration is the right answer but isn't always
reliable over mosh. The fallback: enter copy mode in tmux
(`Shift+PageUp` or mouse wheel up), select with `v`, yank with `y`.
The yanked text goes to tmux's buffer. Paste into any other pane with
`Ctrl-b ]`.

To get text to your local clipboard, the practical answer is either
OSC 52 (if your terminal supports it and you've configured tmux to
pass it through) or dumping the buffer to a scratch file and fetching
it via scp. Pick one and stick with it.

---

## Context and Cost Management

Claude Code sessions accumulate context. Every tool call, its result,
every message — it all grows the context window. At some point,
context size becomes the bottleneck: responses slow down, Claude
starts losing track of early decisions, and cost per response climbs.

**Understanding the signals:**

- `/cost` in a session shows current token usage. Watch this.
- When Claude starts re-asking things you already told it, or
  revisiting decisions it made 20 messages ago, the context is getting
  too large and early content is being truncated or mis-ranked.
- When response latency jumps noticeably, you're likely near the
  context limit.

**When to `/clear`:**

Use `/clear` when:

- You've finished a discrete subtask and are starting something
  unrelated.
- The conversation has gotten circular — you're re-litigating the same
  decisions.
- You're about to do something simple and don't need the accumulated
  context.

`/clear` resets the conversation but not the session state — Claude
still has `CLAUDE.md` loaded, settings still apply, hooks still fire.
It's a cheap reset.

Don't be afraid of it. The instinct to preserve context "just in
case" leads to bloated sessions where Claude is dragging a 50-message
history that's 80% irrelevant. Start fresh when the task changes.

**When to `/compact`:**

Use `/compact` when:

- You want to continue the current thread but are approaching context
  limits.
- There's a long history of tool calls that are no longer relevant to
  the next step, but you want Claude to retain the high-level
  conclusions.

`/compact` asks Claude to summarize the conversation and replace it
with that summary. You lose the detailed tool-call history but keep
the semantic conclusions. This is the right tool for long debugging
sessions: you've tried six things, found the root cause, and now need
to write the fix — compact the trial-and-error and continue with just
the diagnosis.

The downside: the summary is lossy. If you later need to know exactly
which approach you tried and why it failed, it won't be in the
compacted context. Consider writing a quick note file before
compacting if the history is important. A `PreCompact` hook can
snapshot this automatically (see the Hooks section).

**When to restart:**

Restart (kill the pane and run `cc` again) when:

- Auto-compact has triggered and made the session confused. The
  auto-compact summary is sometimes worse than a clean start.
- The session has gone sideways — Claude is in a loop, or has made
  wrong assumptions that are baked into the context — and `/clear`
  isn't enough.
- You want a genuinely fresh start on a new problem.

Restart is free. You lose no files, no settings, no hooks. The only
thing you lose is conversation history — which is often exactly what
you want to lose.

**Auto-compact interaction:**

Auto-compact triggers automatically when the context window is nearly
full. It runs the same process as `/compact` — summarizes and
replaces. This is usually fine but occasionally produces confused
sessions where the summary missed something important.

Signs auto-compact has fired and caused problems: Claude refers to
something with unexpected certainty, or says "as we discussed" and
then gets the details wrong. The solution is to re-state the relevant
context explicitly in your next message, or restart.

You can pre-empt auto-compact by running `/compact` manually before
you hit the threshold, giving you control over when and what gets
summarized.

**Cost discipline for Agent Teams:**

Each teammate has its own context window. A 4-teammate team running
in parallel can burn 4x the tokens of a single session. This is worth
it for genuinely parallel work, not worth it for sequential pipelines
where one agent is always idle.

For the research preset (researcher → fact-checker → writer), only
one teammate is active at a time. The token cost is roughly
equivalent to running them sequentially in a single session, with the
benefit of clean context isolation. For the full-stack preset on a
real feature, all four can be active simultaneously — 4x the cost,
but 4x the throughput if the workstreams don't block each other.

Set a cost budget per session in your head. If a team session is
running past what you'd expect, check `/cost` in the lead and consider
whether the team is actually working in parallel or if you're paying
for four idle panes while one does all the work.

---

## Subagents: Delegate vs Do It Yourself

The Agent tool lets Claude spawn a subagent — a separate Claude
instance that runs a task and returns a result. This is different
from Agent Teams: subagents are spawned by Claude itself to
parallelize work, not by you explicitly.

**When Claude should use a subagent:**

- Independent research or analysis tasks that don't need the lead's
  accumulated context.
- Tasks with a clear output contract: "read these 10 files, extract
  the API signatures, return them as JSON."
- Tasks where context isolation is a feature: a security review
  subagent shouldn't be influenced by the implementation context the
  lead has built up.

**When Claude should do it directly:**

- Tasks that need reasoning accumulated earlier in the conversation.
- Tasks where the result needs immediate integration with what the
  lead is currently doing.
- Simple, fast tasks where the subagent overhead (spawning, context
  injection, result parsing) costs more than doing it inline.

**How to prompt for subagents effectively:**

When asking Claude to delegate, be explicit about the output
contract. Instead of "have a subagent look into the performance
issue," say: "spawn a subagent, give it read access to `src/db/`, and
have it return a list of queries that might be causing N+1 problems,
with file path and line number for each."

The cleaner the output contract, the more useful the subagent
result. Subagents that return "here's everything I found, it's
complicated" create work for the lead to parse. Subagents that return
structured data can be consumed immediately.

**Tool restrictions for subagents:**

When a subagent doesn't need to write files, tell it not to. This is
partly a safety measure and partly a quality measure — a read-only
subagent won't accidentally modify something it's only supposed to
be analyzing. In a skill or agent definition, use `allowed-tools:
Read, Grep, Glob` to enforce read-only access.

**Subagent vs. Agent Teams:**

The distinction that matters: Agent Teams teammates persist for the
session and can receive multiple tasks. Subagents are spawned for
one task and then exit. Use teammates when you have an ongoing
workstream (the frontend teammate will keep getting tasks as the
feature is built out). Use subagents when you have a one-shot task
that doesn't need to persist.

**Agent definitions:**

You can define reusable subagent personalities in
`.claude/agents/<name>.md`:

```markdown
---
name: security-reviewer
description: Security-focused code reviewer. Use for auth, payment, and data handling code.
allowed-tools: Read, Grep, Glob
---

You are a security reviewer. Your job is to find vulnerabilities, not to fix them.

For every piece of code you review:
1. Check for OWASP Top 10 vulnerabilities
2. Flag any hardcoded credentials
3. Identify improper input validation
4. Note overly permissive access controls

Return findings as a structured list: file, line, severity (high/medium/low), description.
Do not suggest fixes — only report findings.
```

When Claude sees code that matches the description, it can
auto-invoke this agent. Or you can explicitly ask: "run the
security-reviewer on `src/auth/`."

---

## Background Tasks and Parallel Execution

Claude Code can fire multiple tool calls in parallel within a single
response. This is distinct from Agent Teams parallelism — it's
single-agent, single-context, multiple simultaneous tools.

**How parallel tool calls work:**

When Claude has multiple independent operations to perform, it can
invoke them simultaneously rather than sequentially. Reading five
files to understand a codebase? All five reads fire at once. Running
three grep searches across different directories? Simultaneous. This
is automatic — Claude decides when to parallelize, you don't control
it directly.

**What you can do to help:**

Frame requests in a way that makes parallelism obvious. Instead of
"find where X is defined, then find where it's called, then find
where it's tested," try "find all three of these: where X is defined,
where it's called, and where it's tested." The second framing makes
it clear these are independent searches that can run at once.

**Background sessions via detach:**

For long tasks (full refactors, large test suite runs, anything that
takes more than 10 minutes), the right pattern is:

1. Give Claude the task.
2. Confirm it understands and has a reasonable plan.
3. `Ctrl-b d` to detach.
4. Come back in 20 minutes.

The session runs on the remote VPS regardless of your mosh connection
state. If mosh drops, reconnect and `cc` to reattach. Claude's
progress is in the pane's scrollback.

**Parallel sessions for independent projects:**

The cc wrapper uses a single session (`SESSION="main"`). If you need
to run Claude on two independent projects simultaneously, use
separate tmux windows within the cc session:

- `Ctrl-b c` — new window
- `Ctrl-b 1`, `Ctrl-b 2` — switch windows
- Run `claude` in each window from the appropriate project directory

Each window has its own scrollback, its own Claude instance, its own
context. They don't share anything except the tmux session.

**Watching background work:**

With a multi-pane team layout, enable `monitor-activity` in the tmux
config and the window status bar marks a `#` when an unfocused pane
produces output. This is a lightweight way to know when a teammate
finishes something without staring at all four panes.

---

## Operational Habits That Compound

These are small habits that each save minutes but add up across a
daily-driver workflow.

**Always start from the right directory.**

The cc wrapper defaults `WORKDIR` to `$HOME`. If your project is at
`~/projects/myapp`, either set `CC_WORKDIR=~/projects/myapp` before
running `cc`, or `cd` to the project inside the session before you
start working. Auto-memory is keyed to the cwd — if you always run
from `$HOME`, all your project-specific memories land in the same
bucket.

**Use `cc sync` after editing workspace files.**

The cron runs every 30 minutes. If you've just added a critical rule
to `AGENTS.md`, don't wait. `cc sync` takes two seconds and resets
`CLAUDE.md` immediately. The cc wrapper already triggers a background
sync on attach — but background means "after you've entered the
session," which may be too late if Claude reads CLAUDE.md during init.

**Checkpoint before major operations.**

Before any task that touches many files or involves irreversible
operations, ask for a plan first (or explicitly use plan mode). The
cost of a planning step is negligible compared to the cost of
unwinding a bad execution.

**Keep the deny list honest.**

Every time Claude tries something you don't want and you stop it
manually, ask whether it should be in the deny list instead. The deny
list encodes learned safety lessons. If you've manually stopped
Claude from editing `openclaw.json` three times, it should be in
deny — which it already is in the shipped config, because it was
learned the hard way.

**Watch for context explosion in long sessions.**

If a session has been running for more than an hour on a complex
task, check `/cost`. If you're past 100k tokens, consider whether the
remaining work benefits from the accumulated context or whether a
`/clear` and a fresh summary would serve better. A fresh start with a
3-sentence context summary often outperforms a bloated session where
Claude is fighting its own history.

**Use the status bar.**

`cc status` shows CLAUDE.md freshness (last sync timestamp), session
state, and available presets. Run it when you're starting a new
session and haven't used cc in a while. A CLAUDE.md that's 45 minutes
stale is fine. One that's 6 hours stale because the cron failed is a
problem.

**Name your panes.**

When spawning a custom team (not a preset), name panes explicitly in
your spawn prompt: "name the panes by role." The cc tmux config shows
pane titles in the border. Named panes make it obvious which teammate
is which when you're navigating a 5-pane layout.

**When in doubt, restart.**

Restart cost is zero. The session takes 3 seconds to come up. The
cost of trying to nurse a confused session is usually higher than
starting fresh. Develop the instinct to kill and restart early,
before you've invested another 20 messages trying to get a broken
session back on track.

---

*This guide reflects the bridge setup as shipped in
`openclaw-claude-bridge` and behavior observed in Claude Code
sessions on Ubuntu 24.04. Some behaviors (especially Agent Teams,
auto-memory, and slash-command templating) are under active
development and may change across Claude Code releases. When a
pattern here conflicts with the official Claude Code docs, trust the
official docs.*
