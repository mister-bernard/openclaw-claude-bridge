#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# OpenClaw + Claude Code bridge — installer
#
# Run once from the cloned repo:
#
#   git clone https://github.com/mister-bernard/openclaw-claude-bridge
#   cd openclaw-claude-bridge
#   bash install.sh
#
# What it does:
#   - Installs bin/cc to ~/.local/bin/cc (adds to PATH if missing)
#   - Installs lib/bridge.sh, presets/, and config/tmux.conf to ~/.openclaw/bridge/
#   - Writes ~/.claude/settings.json (backing up existing)
#   - Runs the first CLAUDE.md sync from your OpenClaw workspace
#   - Registers a cron job that re-syncs CLAUDE.md every 30 minutes
#
# Idempotent: re-runnable safely. Existing CLAUDE.md and settings.json are
# backed up with a timestamp suffix before being overwritten.
# ============================================================================

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
BRIDGE_DIR="${HOME}/.openclaw/bridge"
CLAUDE_DIR="${HOME}/.claude"
CLAUDE_MD="${HOME}/CLAUDE.md"
BIN_DIR="${HOME}/.local/bin"
BACKUP_SUFFIX="$(date +%Y%m%d-%H%M%S)"

OC_WORKSPACE="${OC_WORKSPACE:-${HOME}/.openclaw/workspace}"

C_B=$'\033[1m'; C_BLUE=$'\033[38;5;38m'; C_DIM=$'\033[38;5;244m'
C_RED=$'\033[38;5;203m'; C_GREEN=$'\033[38;5;114m'; C_R=$'\033[0m'

info() { printf "%s[install]%s %s\n" "$C_BLUE" "$C_R" "$*"; }
ok()   { printf "%s[install]%s %s\n" "$C_GREEN" "$C_R" "$*"; }
warn() { printf "%s[install]%s %s\n" "$C_RED" "$C_R" "$*" >&2; }
die()  { warn "$*"; exit 1; }

step() { printf "\n%s==>%s %s%s%s\n" "$C_BLUE" "$C_R" "$C_B" "$*" "$C_R"; }

# ---- Pre-flight checks -------------------------------------------------------

step "pre-flight checks"

command -v tmux   >/dev/null 2>&1 || die "tmux is required (apt install tmux / brew install tmux)"
command -v claude >/dev/null 2>&1 || warn "'claude' not on PATH — install Claude Code before running 'cc'"
command -v crontab >/dev/null 2>&1 || warn "crontab not found — auto-sync will be skipped"

if [[ ! -d "$OC_WORKSPACE" ]]; then
    die "OpenClaw workspace not found at $OC_WORKSPACE (set OC_WORKSPACE=... to override)"
fi

for f in IDENTITY.md USER.md SOUL.md AGENTS.md TOOLS.md; do
    [[ -f "$OC_WORKSPACE/$f" ]] || die "missing workspace file: $OC_WORKSPACE/$f"
done

[[ -d "$CLAUDE_DIR" ]] || mkdir -p "$CLAUDE_DIR"
ok "prereqs OK"

# ---- Install bridge files ----------------------------------------------------

step "installing bridge files to $BRIDGE_DIR"

mkdir -p "$BRIDGE_DIR/lib" "$BRIDGE_DIR/presets"

install -m 0644 "$REPO_DIR/config/tmux.conf" "$BRIDGE_DIR/tmux.conf"
install -m 0755 "$REPO_DIR/lib/bridge.sh"    "$BRIDGE_DIR/lib/bridge.sh"
for p in "$REPO_DIR"/presets/*.md; do
    install -m 0644 "$p" "$BRIDGE_DIR/presets/$(basename "$p")"
done

ok "bridge files installed"

# ---- Install cc binary -------------------------------------------------------

step "installing cc wrapper to $BIN_DIR/cc"

mkdir -p "$BIN_DIR"
install -m 0755 "$REPO_DIR/bin/cc" "$BIN_DIR/cc"

if ! echo ":$PATH:" | grep -q ":$BIN_DIR:"; then
    warn "$BIN_DIR is not on your PATH"
    warn "add this line to your ~/.bashrc or ~/.zshrc:"
    echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

ok "cc installed"

# ---- Write ~/.claude/settings.json -------------------------------------------

step "configuring Claude Code settings"

if [[ -f "$CLAUDE_DIR/settings.json" ]]; then
    cp "$CLAUDE_DIR/settings.json" "$CLAUDE_DIR/settings.json.bak.$BACKUP_SUFFIX"
    info "backed up existing settings.json"
fi
install -m 0644 "$REPO_DIR/config/settings.json" "$CLAUDE_DIR/settings.json"
ok "settings.json written (Agent Teams enabled)"

# ---- First CLAUDE.md sync ----------------------------------------------------

step "generating initial CLAUDE.md"

if [[ -f "$CLAUDE_MD" ]]; then
    cp "$CLAUDE_MD" "${CLAUDE_MD}.bak.$BACKUP_SUFFIX"
    info "backed up existing CLAUDE.md"
fi

OC_WORKSPACE="$OC_WORKSPACE" bash "$BRIDGE_DIR/lib/bridge.sh" sync
ok "CLAUDE.md ready: $CLAUDE_MD"

# ---- Register cron sync ------------------------------------------------------

step "registering cron sync (every 30 minutes)"

if command -v crontab >/dev/null 2>&1; then
    CRON_LINE="*/30 * * * * /usr/bin/env bash $BRIDGE_DIR/lib/bridge.sh sync >> $BRIDGE_DIR/sync.log 2>&1"
    if crontab -l 2>/dev/null | grep -qF "$BRIDGE_DIR/lib/bridge.sh"; then
        info "cron entry already exists — skipping"
    else
        (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
        ok "cron sync registered"
    fi
else
    warn "skipped cron registration (crontab unavailable)"
fi

# ---- Summary -----------------------------------------------------------------

step "done"

cat <<EOF

${C_B}Installed:${C_R}
  $BIN_DIR/cc
  $BRIDGE_DIR/tmux.conf
  $BRIDGE_DIR/lib/bridge.sh
  $BRIDGE_DIR/presets/
  $CLAUDE_DIR/settings.json
  $CLAUDE_MD

${C_B}Next steps:${C_R}
  ${C_BLUE}cc${C_R}                      start a team session
  ${C_BLUE}cc roles${C_R}                list available role presets
  ${C_BLUE}cc preset full-stack${C_R}    print the full-stack preset prompt
  ${C_BLUE}cc help${C_R}                 full usage

Inside the session:
  ${C_DIM}Ctrl-b B${C_R}  horizontal bars layout
  ${C_DIM}Ctrl-b T${C_R}  tiled layout
  ${C_DIM}Ctrl-b d${C_R}  detach (session keeps running)

EOF
