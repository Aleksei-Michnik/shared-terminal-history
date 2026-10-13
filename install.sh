#!/usr/bin/env bash
# Install shared-terminal-history for the current user.
# Idempotent: safe to re-run to upgrade an existing install.
#
#   ./install.sh                 install, and offer to wire up detected agents
#   ./install.sh --no-agents     install the shell side only
#   ./install.sh --max 50000     keep 50000 commands instead of the 19999 default

set -euo pipefail

REPO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
INSTALL_DIR="${SHARED_HISTORY_HOME:-$HOME/.config/shared-terminal-history}"
DATA_DIR="${SHARED_HISTORY_DATA_DIR:-$HOME/.local/share/shared-terminal-history}"
BIN_DIR="${SHARED_HISTORY_BIN_DIR:-$HOME/.local/bin}"
BASHRC="${SHARED_HISTORY_BASHRC:-$HOME/.bashrc}"
MAX_COMMANDS=19999
WIRE_AGENTS=1

while [ $# -gt 0 ]; do
    case $1 in
        --no-agents) WIRE_AGENTS=0; shift ;;
        --max)       MAX_COMMANDS=${2:?--max needs a value}; shift 2 ;;
        -h|--help)   sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done

say()  { printf '  %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

echo "shared-terminal-history"
echo

# ---------------------------------------------------------------- prerequisites
if ((BASH_VERSINFO[0] < 4)); then
    warn "bash ${BASH_VERSION} detected; bash 4.4+ is required (macOS ships 3.2 — try: brew install bash)"
    exit 1
fi
command -v jq    >/dev/null 2>&1 || warn "jq not found — agent hooks need it (apt install jq / brew install jq)"
command -v flock >/dev/null 2>&1 || warn "flock not found — appends will be unlocked but still work"

# ---------------------------------------------------------------------- install
mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$BIN_DIR"
install -m 0644 "$REPO_DIR/shell/shell-init.bash" "$INSTALL_DIR/shell-init.bash"
install -m 0755 "$REPO_DIR/hooks/record-command"  "$INSTALL_DIR/record-command"
install -m 0755 "$REPO_DIR/bin/shared-history"    "$BIN_DIR/shared-history"
say "installed into $INSTALL_DIR and $BIN_DIR"

# Config is written once and then left alone, so re-running never clobbers edits.
if [ ! -f "$INSTALL_DIR/config" ]; then
    cat >"$INSTALL_DIR/config" <<EOF
# shared-terminal-history configuration. Sourced by shell-init.bash and shared-history.

# How many commands to keep. -1 for unlimited.
SHARED_HISTORY_MAX=$MAX_COMMANDS

# The shared store. Every terminal and every agent hook appends here.
# SHARED_HISTFILE="\$HOME/.bash_history"

# Timestamp format shown by \`history\`.
# SHARED_HISTORY_TIMEFORMAT='%F %T  '
EOF
    say "wrote $INSTALL_DIR/config (max $MAX_COMMANDS commands)"
else
    say "kept existing $INSTALL_DIR/config"
fi

# ----------------------------------------------------------------------- bashrc
# The block goes at the END of .bashrc: anything sourced later that assigns
# PROMPT_COMMAND= would otherwise drop the sync.
MARKER='shared-terminal-history/shell-init.bash'

# Bash truncates the history file the moment HISTFILESIZE is assigned a number, so a line
# such as Ubuntu's stock HISTFILESIZE=2000 cuts the shared history back at every new
# terminal, before the block at the end can raise the cap. Such lines are commented out
# behind DISABLED, which uninstall.sh strips again; `shared-history doctor` checks for them.
DISABLED='# [shared-terminal-history] '
TRUNCATING="^[[:space:]]*((export|declare|typeset)[[:space:]]+(-[[:alpha:]]+[[:space:]]+)?)?HISTFILESIZE=[\"']?[0-9]+[\"']?[[:space:]]*(#.*)?\$"
truncating=$(grep -nE "$TRUNCATING" "$BASHRC" 2>/dev/null || true)

if [ -f "$BASHRC" ] && { [ -n "$truncating" ] || ! grep -qF "$MARKER" "$BASHRC"; }; then
    cp "$BASHRC" "$BASHRC.bak-shared-terminal-history"
fi

if [ -n "$truncating" ]; then
    tmp=$(mktemp)
    awk -v lines="$(printf '%s\n' "$truncating" | cut -d: -f1 | tr '\n' ' ')" -v tag="$DISABLED" '
        BEGIN { n = split(lines, l, " "); for (i = 1; i <= n; i++) hit[l[i]] = 1 }
        NR in hit { $0 = tag $0 }
        { print }
    ' "$BASHRC" >"$tmp"
    cat "$tmp" >"$BASHRC"
    rm -f "$tmp"
    say "commented out what truncated the history at every new terminal (backup: $BASHRC.bak-shared-terminal-history):"
    printf '%s\n' "$truncating" | sed 's/^\([0-9]*\):/      line \1: /'
fi

if grep -qF "$MARKER" "$BASHRC" 2>/dev/null; then
    say "$BASHRC already sources shell-init.bash"
else
    cat >>"$BASHRC" <<'EOF'

# shared-terminal-history — one history across all terminals.
# Keep this LAST: anything below that assigns PROMPT_COMMAND= will disable the sync.
if [ -r "$HOME/.config/shared-terminal-history/shell-init.bash" ]; then
    . "$HOME/.config/shared-terminal-history/shell-init.bash"
fi
EOF
    say "appended the source block to $BASHRC (backup: $BASHRC.bak-shared-terminal-history)"
fi

# A PROMPT_COMMAND of its own that runs `history -a` and friends syncs a second time at
# every prompt. Only reported: such a line may carry other work too.
syncing=$(grep -nE '^[^#]*PROMPT_COMMAND.*history[[:space:]]+-[acnr]' "$BASHRC" 2>/dev/null || true)
if [ -n "$syncing" ]; then
    warn "these lines sync the history as well, so every prompt syncs twice; their history part can go:"
    printf '%s\n' "$syncing" | sed 's/^\([0-9]*\):/      line \1: /' >&2
fi

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not on your PATH — add it to use the \`shared-history\` command" ;;
esac

# ------------------------------------------------------------------ agent hooks
if [ "$WIRE_AGENTS" = 1 ]; then
    echo
    echo "agents:"
    if [ -d "$HOME/.claude" ]; then
        if command -v jq >/dev/null 2>&1; then
            "$REPO_DIR/agents/install-claude-code.sh" && say "Claude Code wired up"
        else
            warn "Claude Code detected but jq is missing; see agents/claude-code.md"
        fi
    else
        say "Claude Code not detected — see agents/ for other agents"
    fi
fi

echo
echo "Done. Open a new terminal, or run:  . $INSTALL_DIR/shell-init.bash"
echo "Then check it with:                 shared-history status"
