# openclaw-claude-bridge

A bridge between [OpenClaw](https://openclaw.ai) and
[Claude Code](https://claude.com/claude-code) that gives you a single
daily-driver command — `cc` — for running Claude Code with:

- A unified `CLAUDE.md` auto-generated from your OpenClaw workspace
- Claude Code's experimental **Agent Teams** mode turned on
- A dedicated, Mosh-friendly tmux session with 100k scrollback and
  working mouse wheel
- Role presets for spawning research / full-stack / debug teams in one
  paste
- Cockpit-style status bar and layout shortcuts

It runs on an isolated tmux socket (`-L cc`), so it never touches your
personal tmux configuration or collides with other sessions you have
running.

## Install

```bash
git clone https://github.com/mister-bernard/openclaw-claude-bridge
cd openclaw-claude-bridge
bash install.sh
```

The installer drops a handful of files and leaves the rest of your
machine alone:

| Path                                          | What it is                          |
| --------------------------------------------- | ----------------------------------- |
| `~/.local/bin/cc`                             | The `cc` daily-driver wrapper       |
| `~/.openclaw/bridge/tmux.conf`                | Mosh-friendly tmux config for `cc`  |
| `~/.openclaw/bridge/lib/bridge.sh`            | CLAUDE.md synthesizer               |
| `~/.openclaw/bridge/presets/*.md`             | Role preset prompts                 |
| `~/.claude/settings.json`                     | Claude Code config (backed up)      |
| `~/CLAUDE.md`                                 | Synthesized workspace (backed up)   |

A cron job is registered to re-sync `~/CLAUDE.md` every 30 minutes. Make
sure `~/.local/bin` is on your `PATH`; the installer will tell you if it
isn't.

## Prereqs

- `tmux` 3.0+
- `claude` CLI ([Claude Code](https://claude.com/claude-code)) on `PATH`
- An OpenClaw workspace at `~/.openclaw/workspace/` containing:
  `IDENTITY.md`, `USER.md`, `SOUL.md`, `AGENTS.md`, `TOOLS.md`
  (override with `OC_WORKSPACE=...`)

## Daily use

```bash
cc                      # start or attach the team session
cc sync                 # regenerate ~/CLAUDE.md from the workspace
cc status               # show session and workspace state
cc roles                # list available role presets
cc preset full-stack    # print the full-stack preset prompt (paste into lead)
cc kill                 # kill the team session (with confirmation)
cc help                 # full usage
```

Inside the session (prefix = `Ctrl-b`):

| Keys                 | What it does                                 |
| -------------------- | -------------------------------------------- |
| `Ctrl-b B`           | Horizontal bars layout (stacked top-to-bottom) |
| `Ctrl-b H`           | Vertical columns layout                      |
| `Ctrl-b T`           | Tiled layout                                 |
| Mouse wheel          | Scroll back (100k lines)                     |
| `Shift+PageUp/Down`  | Keyboard scrollback                          |
| `Alt+Arrow`          | Jump between panes                           |
| `Ctrl-b r`           | Reload tmux config                           |
| `Ctrl-b d`           | Detach — session keeps running               |

## Agent Teams: the lead-spawns-teammates model

Agent Teams is **not** six peer sessions. It's **one lead + N teammates**.
You start a single `claude` process (that's the lead) and ask it in plain
English to spawn teammates. Claude Code itself creates the new tmux panes
and manages the roster. The panes coordinate through a shared task list
and a `SendMessage` tool — you talk to the lead, and the lead routes.

```
You: create a team with 4 teammates in split-pane tmux mode.
     roles: backend, frontend, tests, ops.
     assign non-overlapping file ownership so they don't clobber each other.
```

Or skip the typing and use a preset:

```bash
cc preset full-stack    # prints the prompt
# copy, paste into the lead
```

### Role presets

| Preset       | Teammates | Use case                              |
| ------------ | --------- | ------------------------------------- |
| `research`   | 3         | researcher + fact-checker + writer    |
| `full-stack` | 4         | backend + frontend + tests + ops      |
| `debug`      | 3         | reproducer + fixer + verifier         |
| `solo`       | 0         | no team, just the lead                |

Each preset enforces strict, non-overlapping file ownership — Agent Teams
has no file locking, so two teammates editing the same file silently
clobber each other. Splitting ownership by directory is the cheapest way
to prevent that.

### Sweet spot

The docs call **3–5 teammates** the sweet spot. Beyond that:

- Token cost scales linearly (each teammate has its own context window)
- Coordination overhead starts dominating
- File conflict surface grows quadratically

Six is the upper bound that still feels useful. Start with four, measure,
add more only if the workstreams are genuinely independent.

## Mosh + scrollback

Mosh has no scrollback of its own — it replaces your terminal's buffer
with its own screen. **Tmux is the scrollback** when you're over Mosh.

The tmux config shipped here does three things that matter for Mosh:

1. **`set -g history-limit 100000`** — 100k lines per pane
2. **`set -g mouse on`** with smooth wheel → copy-mode handoff
3. **`set -s escape-time 0`** — no ESC key lag (Mosh amplifies even a few ms)

If the wheel isn't scrolling inside a Claude Code pane, you're probably
not loading this config. Run `cc status` — if the session isn't labeled
`cc` on the `cc` socket, something else is attaching. Kill it and
re-`cc`.

Keyboard scrollback: `Shift+PageUp` / `Shift+PageDown` works everywhere,
including inside Claude Code's TUI.

## Architecture

```
┌────────────────┐    ┌──────────────────────────┐
│ OpenClaw       │    │ Claude Code (lead + N)   │
│ workspace/     │    │                          │
│  ├ IDENTITY.md │───▶│ reads ~/CLAUDE.md        │
│  ├ USER.md     │    │ (synthesized every 30m)  │
│  ├ SOUL.md     │    │                          │
│  ├ AGENTS.md   │    │ tmux -L cc (isolated)    │
│  └ TOOLS.md    │    │  ├ pane 1: lead          │
└────────────────┘    │  ├ pane 2: teammate      │
       ▲              │  ├ pane 3: teammate      │
       │              │  └ pane N: teammate      │
  cc sync             └──────────────────────────┘
  (manual or cron)
```

`install.sh` is the one-time installer. `cc` is the daily driver.
`lib/bridge.sh` does the actual `CLAUDE.md` synthesis and is also what
the cron job invokes.

## Sync model

`~/CLAUDE.md` is regenerated from scratch every sync — no merge, no diff.
Edit the source files in `~/.openclaw/workspace/` and run `cc sync`. If
you edit `~/CLAUDE.md` directly, your changes will be overwritten on the
next sync (the previous version is saved as `~/CLAUDE.md.bak.<timestamp>`,
and the last 5 backups are kept).

The sync extracts specific sections from the workspace files:

- From `AGENTS.md`: everything between `# RULES` and `# DELEGATION`
- From `TOOLS.md`: everything between `## Key services` and `## Pending`
- `IDENTITY.md`, `USER.md`, `SOUL.md`: full file (minus HTML comments)

If you use different section markers, edit `lib/bridge.sh`.

## Uninstall

```bash
# remove files
rm -f ~/.local/bin/cc ~/CLAUDE.md
rm -rf ~/.openclaw/bridge

# remove cron entry
crontab -l | grep -v "/.openclaw/bridge/lib/bridge.sh" | crontab -

# restore your old Claude Code settings if you want
ls ~/.claude/settings.json.bak.*   # pick one and mv it back
```

## License

MIT — see `LICENSE`.
