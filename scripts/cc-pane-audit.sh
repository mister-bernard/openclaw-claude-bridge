#!/usr/bin/env bash
# cc-pane-audit.sh — Hourly sanity check on cc tmux panes + tokenburn-api.
#
# Runs from cc-pane-audit.timer (every hour). Two checks:
#
#   1. Per-pane account audit. For every pane on the `cc` tmux socket, read
#      the claude descendant's HOME from /proc and confirm it matches the
#      account intended by the pane's session name (main → active account,
#      main-B → B, main-<N> numeric → active). Mismatches → log + TG.
#
#   2. tokenburn-api liveness. Probe http://127.0.0.1:18795/health. If down
#      for TWO consecutive ticks → TG once. State file dedupes so we never
#      spam: alert on entering down-streak, recovery note on exit. The
#      streak counter persists in ~/.openclaw/state/cc-pane-audit-state.json.
#
# All-clear runs are silent except for a single audit-log line. We do NOT
# TG when everything is fine — preserves alert hygiene per recent work.
#
# Outputs:
#   ~/.openclaw/state/cc-pane-audit.log         — one line per run (rotated)
#   ~/.openclaw/state/cc-pane-audit-state.json  — dedupe state for TG sends
#
# Manual run: bash ~/scripts/cc-pane-audit.sh [--verbose]

set -uo pipefail

VERBOSE=0
[[ "${1:-}" == "--verbose" || "${1:-}" == "-v" ]] && VERBOSE=1

# --- environment (cron-safe) -------------------------------------------------
export PATH="/home/openclaw/.local/bin:/home/linuxbrew/.linuxbrew/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

# Pull TELEGRAM_BOT_TOKEN + G_TELEGRAM_ID into env so tg-send-logged.sh
# (a separate process) inherits them. The .env uses bare KEY=VAL (no
# `export`), so we wrap the source in `set -a` to auto-export every var.
if [[ -f /home/openclaw/.openclaw/.env ]]; then
    set +u
    set -a
    # shellcheck disable=SC1091
    source /home/openclaw/.openclaw/.env 2>/dev/null || true
    set +a
    set -u
fi

# --- config ------------------------------------------------------------------
SOCKET="cc"
TMUX_CONF="/home/openclaw/.openclaw/bridge/tmux.conf"
ACCOUNTS_FILE="/home/openclaw/.tokenburn.json"
STATE_DIR="/home/openclaw/.openclaw/state"
LOG_FILE="${STATE_DIR}/cc-pane-audit.log"
STATE_FILE="${STATE_DIR}/cc-pane-audit-state.json"
TG_SEND="/home/openclaw/scripts/tg-send-logged.sh"
TG_CHAT_ID="${G_TELEGRAM_ID:-39172309}"
TG_LABEL="cc-pane-audit"
TOKENBURN_HEALTH="http://127.0.0.1:18795/health"

mkdir -p "$STATE_DIR"
[[ -f "$STATE_FILE" ]] || echo '{"tokenburn_down_streak":0,"tokenburn_alerted":false,"last_mismatch_hash":""}' > "$STATE_FILE"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(ts)] $*" >> "$LOG_FILE"; (( VERBOSE )) && echo "$*"; }

# Rotate the log if it gets large (keep ≤500 KB, ≤2 backups).
if [[ -f "$LOG_FILE" ]] && (( $(stat -c%s "$LOG_FILE") > 500000 )); then
    mv -f "$LOG_FILE.1" "$LOG_FILE.2" 2>/dev/null || true
    mv -f "$LOG_FILE" "$LOG_FILE.1"
    : > "$LOG_FILE"
fi

# tmux wrapper
tmux_cc() { tmux -L "$SOCKET" -f "$TMUX_CONF" "$@"; }

# --- state helpers -----------------------------------------------------------
# state_get <key>           → prints stored value (empty if missing)
# state_set <key> <kind> <val>  kind is one of: str | int | bool
state_get() {
    KEY="$1" STATE_FILE="$STATE_FILE" python3 -c "
import json, os
d = json.load(open(os.environ['STATE_FILE']))
v = d.get(os.environ['KEY'], '')
if isinstance(v, bool):
    print('true' if v else 'false')
else:
    print(v)
" 2>/dev/null
}
state_set() {
    KEY="$1" KIND="$2" VAL="$3" STATE_FILE="$STATE_FILE" python3 -c "
import json, os
p = os.environ['STATE_FILE']
d = json.load(open(p))
k, kind, v = os.environ['KEY'], os.environ['KIND'], os.environ['VAL']
if kind == 'int':
    d[k] = int(v)
elif kind == 'bool':
    d[k] = v.lower() in ('true','1','yes')
else:
    d[k] = v
open(p, 'w').write(json.dumps(d) + '\n')
" 2>/dev/null
}

tg_send() {
    local msg="$1"
    if [[ -x "$TG_SEND" ]]; then
        "$TG_SEND" "$TG_CHAT_ID" "$TG_LABEL" "$msg" >> "$LOG_FILE" 2>&1 || \
            log "tg_send: helper exited non-zero (msg suppressed?)"
    else
        log "tg_send: $TG_SEND missing — cannot deliver: $msg"
    fi
}

# --- 1. pane audit -----------------------------------------------------------
# Reuse `cc panes` for the heavy lifting, but ALSO emit a JSON summary
# so this script can act on it.
PANE_REPORT=$(ACCOUNTS_FILE="$ACCOUNTS_FILE" SOCKET="$SOCKET" TMUX_CONF="$TMUX_CONF" python3 <<'PY'
import json, os, sys, subprocess

ACCOUNTS_FILE = os.environ["ACCOUNTS_FILE"]
SOCKET = os.environ["SOCKET"]
TMUX_CONF = os.environ["TMUX_CONF"]

try:
    raw = subprocess.check_output(
        ["tmux", "-L", SOCKET, "-f", TMUX_CONF, "list-panes", "-aF",
         "#{session_name}|#{pane_index}|#{pane_pid}|#{pane_left}"],
        stderr=subprocess.DEVNULL,
    ).decode().strip()
except subprocess.CalledProcessError:
    print(json.dumps({"panes_total": 0, "panes_with_claude": 0, "mismatches": []}))
    sys.exit(0)

if not raw:
    print(json.dumps({"panes_total": 0, "panes_with_claude": 0, "mismatches": []}))
    sys.exit(0)

home_to_id, id_to_home = {}, {}
try:
    cfg = json.load(open(ACCOUNTS_FILE))
    for a in cfg.get("accounts", []):
        h = a.get("claude_home")
        if h:
            real = os.path.realpath(h.rstrip("/"))
            home_to_id[real] = a.get("id", "?")
            id_to_home[a.get("id", "?")] = real
    default_id = cfg.get("active_account", "A")
except Exception:
    default_id = "A"
    cfg = {}

DEFAULT_SESSION = "main"

def expected_acct(sname):
    if sname == DEFAULT_SESSION:
        return default_id
    if sname.startswith(DEFAULT_SESSION + "-"):
        tail = sname[len(DEFAULT_SESSION) + 1:]
        if tail.isdigit():
            return default_id
        if tail.upper() in id_to_home:
            return tail.upper()
    return None

def read_home(pid):
    try:
        env = open(f"/proc/{pid}/environ", "rb").read().split(b"\x00")
    except Exception:
        return None
    for kv in env:
        if kv.startswith(b"HOME="):
            return kv[5:].decode(errors="replace").rstrip("/")
    return None

def claude_home_of(pane_pid):
    seen, stack = set(), [pane_pid]
    while stack:
        cur = stack.pop()
        if cur in seen:
            continue
        seen.add(cur)
        try:
            kids = open(f"/proc/{cur}/task/{cur}/children").read().split()
        except Exception:
            continue
        for c in kids:
            try:
                cmd = open(f"/proc/{c}/cmdline", "rb").read().replace(b"\x00", b" ").decode(errors="replace")
            except Exception:
                continue
            if "claude" in cmd:
                return read_home(c)
            stack.append(c)
    return None

panes_total = 0
panes_with_claude = 0
mismatches = []
for line in raw.splitlines():
    parts = line.split("|")
    if len(parts) < 4:
        continue
    sname, pidx, ppid, _ = parts[0], parts[1], parts[2], parts[3]
    panes_total += 1
    try:
        ppid_i = int(ppid)
    except ValueError:
        continue
    chome = claude_home_of(ppid_i)
    if not chome:
        continue
    panes_with_claude += 1
    actual = home_to_id.get(os.path.realpath(chome), "?")
    expected = expected_acct(sname)
    if expected and actual != "?" and actual != expected:
        mismatches.append({
            "session": sname, "pane": pidx, "expected": expected,
            "actual": actual, "home": chome, "pid": ppid,
        })

print(json.dumps({
    "panes_total": panes_total,
    "panes_with_claude": panes_with_claude,
    "mismatches": mismatches,
}))
PY
)

panes_total=$(echo "$PANE_REPORT" | python3 -c "import json,sys; print(json.load(sys.stdin)['panes_total'])")
panes_with_claude=$(echo "$PANE_REPORT" | python3 -c "import json,sys; print(json.load(sys.stdin)['panes_with_claude'])")
mismatch_count=$(echo "$PANE_REPORT" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['mismatches']))")

if (( mismatch_count > 0 )); then
    # Compose a TG-friendly mismatch summary. NB: heredocs take over stdin,
    # so pipe-feeding python via `echo | python3 <<EOF` does NOT work — the
    # heredoc wins. We pass the JSON report via env var instead.
    SUMMARY=$(PANE_REPORT="$PANE_REPORT" python3 <<'PY'
import json, os
d = json.loads(os.environ["PANE_REPORT"])
lines = [f"cc pane audit: {len(d['mismatches'])} mismatch(es)"]
for m in d["mismatches"]:
    lines.append(f"  • {m['session']}:{m['pane']} expected={m['expected']} actual={m['actual']} home={m['home']} pid={m['pid']}")
print("\n".join(lines))
PY
    )
    # Hash so we only re-alert when the mismatch set changes.
    HASH=$(echo "$SUMMARY" | sha256sum | cut -c1-12)
    LAST_HASH=$(state_get last_mismatch_hash)
    if [[ "$HASH" != "$LAST_HASH" ]]; then
        log "MISMATCH (new) — $mismatch_count pane(s); alerting"
        log "$SUMMARY"
        tg_send "$SUMMARY"
        state_set last_mismatch_hash str "$HASH"
    else
        log "MISMATCH (unchanged) — $mismatch_count pane(s); already alerted"
    fi
else
    # Clear stale mismatch state on recovery (silent — no TG).
    LAST_HASH=$(state_get last_mismatch_hash)
    if [[ -n "$LAST_HASH" ]]; then
        log "mismatches cleared (was: $LAST_HASH)"
        state_set last_mismatch_hash str ""
    fi
fi

# --- 2. tokenburn-api liveness ----------------------------------------------
if curl -sf --max-time 4 "$TOKENBURN_HEALTH" > /dev/null 2>&1; then
    # Up. If we previously alerted (streak ≥ 2), send recovery.
    PREV_STREAK=$(state_get tokenburn_down_streak)
    PREV_ALERTED=$(state_get tokenburn_alerted)
    if [[ "$PREV_ALERTED" == "true" ]]; then
        log "tokenburn-api recovered (was down $PREV_STREAK tick(s))"
        tg_send "tokenburn-api recovered (was down $PREV_STREAK tick(s))"
    fi
    state_set tokenburn_down_streak int 0
    state_set tokenburn_alerted bool false
else
    PREV_STREAK=$(state_get tokenburn_down_streak)
    NEW_STREAK=$((PREV_STREAK + 1))
    log "tokenburn-api DOWN (streak=$NEW_STREAK)"
    state_set tokenburn_down_streak int "$NEW_STREAK"
    if (( NEW_STREAK >= 2 )); then
        PREV_ALERTED=$(state_get tokenburn_alerted)
        if [[ "$PREV_ALERTED" != "true" ]]; then
            tg_send "tokenburn-api DOWN (2 consecutive ticks) — $TOKENBURN_HEALTH not responding"
            state_set tokenburn_alerted bool true
        fi
    fi
fi

log "audit ok — panes_total=$panes_total panes_with_claude=$panes_with_claude mismatches=$mismatch_count"
exit 0
