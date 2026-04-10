# openclaw-claude-bridge

A small installer that wires [OpenClaw](https://openclaw.ai) and
[Claude Code](https://claude.com/claude-code) together on the same machine
so they can share context, rules, and memory — plus a tmux launcher for
running Claude Code Agent Teams in split panes.

## What it does

1. **Generates a unified `~/CLAUDE.md`** by concatenating your OpenClaw
   workspace markdown files (`IDENTITY.md`, `USER.md`, `SOUL.md`,
   `AGENTS.md`, `TOOLS.md`) into a single file Claude Code reads on every
   session. Edit the source files, re-run the sync, and Claude Code picks
   up the changes.

2. **Configures `~/.claude/settings.json`** with:
   - `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` so multiple Claude Code panes
     can see each other as teammates and hand work off with `Shift+Down`.
   - A conservative allow/deny list for Bash, Read, and Write permissions.

3. **Installs `~/bin/cc-teams`** — a tmux launcher that opens N Claude Code
   instances in split panes inside a single session. One command, several
   agents, all sharing the same filesystem.

4. **Registers a cron job** that re-syncs `CLAUDE.md` every 30 minutes so
   changes to your OpenClaw workspace flow into Claude Code automatically.

5. **Writes shell aliases** (`cc`, `cct`, `ocw`, `ocsync`, …) to
   `~/.openclaw/bridge/aliases.sh`. Source it from your `.bashrc`.

## Expected OpenClaw workspace layout

The installer expects these files to exist under
`~/.openclaw/workspace/` (override with `OC_WORKSPACE=...`):

| File          | Purpose                                              |
| ------------- | ---------------------------------------------------- |
| `IDENTITY.md` | Who the agent is — name, origin, philosophy          |
| `USER.md`     | Who the operator is — name, preferences, handles     |
| `SOUL.md`     | Voice, tone, anti-sycophancy rules                   |
| `AGENTS.md`   | Operational rules. Must contain a `# RULES` section, optionally followed by `# DELEGATION` (only `# RULES` is imported into `CLAUDE.md`). |
| `TOOLS.md`    | Tools and services reference. A `## Key services` heading marks the start of the section that gets imported. |

If any of these are missing the installer aborts with an error listing
which one.

## Install

```bash
git clone https://github.com/mister-bernard/openclaw-claude-bridge.git
cd openclaw-claude-bridge
bash openclaw-bridge.sh
```

The installer is idempotent — existing `~/CLAUDE.md` and
`~/.claude/settings.json` are backed up with a timestamp before being
overwritten, and the cron entry is only added if it doesn't already exist.

## Running multiple Claude Code agents in tmux

Once the bridge is installed:

```bash
cc-teams 3        # 3 Claude Code instances in a tiled tmux layout
cc-teams attach   # reattach to the session from another terminal
cc-teams kill     # stop them all
```

Inside the session, `Shift+Down` cycles between teammates when Agent Teams
mode is enabled. Each pane is a full Claude Code session and can delegate
to the others.

## Sync

Manual:

```bash
ocsync                            # if you sourced aliases.sh
bash ~/.openclaw/bridge/sync.sh   # otherwise
```

Automatic: every 30 minutes via cron (installed by the bridge).

## Uninstall

```bash
crontab -l | grep -v "bridge/sync.sh" | crontab -
rm -f ~/CLAUDE.md ~/bin/cc-teams
rm -rf ~/.openclaw/bridge
# Restore your original settings.json from the .bak file in ~/.claude/
```

## Caveats

- The installer overwrites `~/CLAUDE.md` and `~/.claude/settings.json`.
  Backups are taken, but review the diff before you rely on your old
  values.
- The generated `CLAUDE.md` assumes the sections and heading structure
  described above. If your `AGENTS.md` or `TOOLS.md` uses different
  markers, edit the `awk` extractions in `openclaw-bridge.sh`.
- `cc-teams` assumes `claude` is on your `PATH`.

## License

MIT — see `LICENSE`.
