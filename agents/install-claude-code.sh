#!/usr/bin/env bash
# Register the shared-terminal-history recorder as a Claude Code Bash hook.
# Idempotent: re-running replaces this project's entries and leaves everything else alone.
#
# Claude Code runs each Bash tool call as a non-interactive `bash -c`, which never
# sources ~/.bashrc — so a hook is the only way those commands reach the history.

set -euo pipefail

SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
INSTALL_DIR="${SHARED_HISTORY_HOME:-$HOME/.config/shared-terminal-history}"
RECORDER="$INSTALL_DIR/record-command"

command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }
[ -x "$RECORDER" ] || { echo "recorder not installed at $RECORDER — run install.sh first" >&2; exit 1; }

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || echo '{}' >"$SETTINGS"

# A malformed settings.json silently disables every setting in it — refuse to touch it.
jq -e . "$SETTINGS" >/dev/null 2>&1 || { echo "$SETTINGS is not valid JSON — fix it first" >&2; exit 1; }

cp "$SETTINGS" "$SETTINGS.bak-shared-terminal-history"

# PostToolUse fires only on success and PostToolUseFailure only on failure, so both are
# needed to cover every command that actually ran. PreToolUse is deliberately not used:
# it fires before the permission prompt, so it would log commands the user declined.
tmp=$(mktemp)
jq --arg cmd "$RECORDER" '
    def entry: {
        matcher: "Bash",
        hooks: [{ type: "command", command: $cmd, args: ["--source", "claude-code"], timeout: 10 }]
    };
    # Drop any previous entry of ours, keep everyone else, then append the current one.
    def wire($event):
        .hooks[$event] = (
            ((.hooks[$event] // []) | map(select(
                [.hooks[]? | select(.command | test("record-command"))] | length == 0
            ))) + [entry]
        );
    .hooks = (.hooks // {}) | wire("PostToolUse") | wire("PostToolUseFailure")
' "$SETTINGS" >"$tmp"

jq -e . "$tmp" >/dev/null 2>&1 || { echo "refusing to write invalid JSON" >&2; rm -f "$tmp"; exit 1; }
mv "$tmp" "$SETTINGS"

echo "registered PostToolUse + PostToolUseFailure Bash hooks in $SETTINGS"
echo "backup: $SETTINGS.bak-shared-terminal-history"
