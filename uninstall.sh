#!/usr/bin/env bash
# Remove shared-terminal-history. Your ~/.bash_history is never touched.

set -euo pipefail

INSTALL_DIR="${SHARED_HISTORY_HOME:-$HOME/.config/shared-terminal-history}"
DATA_DIR="${SHARED_HISTORY_DATA_DIR:-$HOME/.local/share/shared-terminal-history}"
BIN_DIR="${SHARED_HISTORY_BIN_DIR:-$HOME/.local/bin}"
BASHRC="${SHARED_HISTORY_BASHRC:-$HOME/.bashrc}"
SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

say() { printf '  %s\n' "$*"; }

# .bashrc: drop our block, and restore the HISTFILESIZE lines install.sh commented out.
DISABLED='# [shared-terminal-history] '
if grep -qF -e 'shared-terminal-history/shell-init.bash' -e "$DISABLED" "$BASHRC" 2>/dev/null; then
    cp "$BASHRC" "$BASHRC.bak-uninstall"
    awk -v tag="$DISABLED" '
        /^# shared-terminal-history — one history across all terminals\.$/ { skip = 1 }
        skip && /^fi$/ { skip = 0; next }
        skip { next }
        index($0, tag) == 1 { $0 = substr($0, length(tag) + 1) }
        { print }
    ' "$BASHRC.bak-uninstall" >"$BASHRC"
    say "removed the block from $BASHRC (backup: $BASHRC.bak-uninstall)"
    if grep -qF "$DISABLED" "$BASHRC.bak-uninstall"; then
        say "restored the HISTFILESIZE lines the installer had commented out"
    fi
fi

# Claude Code: drop only our hook entries.
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1 && jq -e . "$SETTINGS" >/dev/null 2>&1; then
    if jq -e '.. | objects | select(.command? // "" | test("record-command"))' "$SETTINGS" >/dev/null 2>&1; then
        tmp=$(mktemp)
        jq '
            def strip($event):
                if (.hooks[$event] // null) == null then .
                else .hooks[$event] = ((.hooks[$event]
                        | map(select([.hooks[]? | select(.command | test("record-command"))] | length == 0))
                        | map(select((.hooks | length) > 0))))
                     | (if (.hooks[$event] | length) == 0 then .hooks |= del(.[$event]) else . end)
                end;
            strip("PostToolUse") | strip("PostToolUseFailure")
            | (if (.hooks | length) == 0 then del(.hooks) else . end)
        ' "$SETTINGS" >"$tmp" && jq -e . "$tmp" >/dev/null 2>&1 && mv "$tmp" "$SETTINGS"
        say "removed the hook entries from $SETTINGS"
    fi
fi

rm -f  "$BIN_DIR/shared-history"
rm -rf "$INSTALL_DIR"
say "removed $INSTALL_DIR and $BIN_DIR/shared-history"

echo
echo "Kept: ~/.bash_history and the agent audit log in $DATA_DIR"
echo "Delete the audit log yourself if you want it gone:  rm -rf $DATA_DIR"
