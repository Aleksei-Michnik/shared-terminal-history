# Claude Code

**Status:** supported and verified (Claude Code 2.1.211, bash 5.1.16).

## Why a hook is required

Claude Code runs every Bash tool call as a non-interactive `bash -c`. Inside one of those shells:

```
$-        = hmtBc      # no "i" — not interactive
HISTFILE  = (empty)    # no history file
~/.bashrc              # never sourced
```

So no shell configuration can capture Claude's commands. The hook layer is the only option.

## Automatic setup

```bash
./agents/install-claude-code.sh
```

`install.sh` runs this for you when it detects `~/.claude`. It is idempotent: it backs up
`settings.json`, refuses to touch it if it is not valid JSON, removes any previous entry of
ours, then appends the current one.

## Manual setup

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/home/YOU/.config/shared-terminal-history/record-command",
            "args": ["--source", "claude-code"],
            "timeout": 10
          }
        ]
      }
    ],
    "PostToolUseFailure": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/home/YOU/.config/shared-terminal-history/record-command",
            "args": ["--source", "claude-code"],
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

Merge this into your existing settings — do not replace the file, or you will drop your
permissions and other configuration.

> **Use an absolute path.** With `args` present, Claude Code spawns the command directly with no
> shell, so `$HOME` and `~` are **not** expanded. If you would rather use `$HOME`, omit the
> `args` key and put the flags in the command string — without `args` the command runs through a
> shell, which does expand it:
> ```json
> { "type": "command",
>   "command": "$HOME/.config/shared-terminal-history/record-command --source claude-code" }
> ```

## Why both events

| Event | Fires |
|---|---|
| `PostToolUse` | only after a Bash call **succeeds** |
| `PostToolUseFailure` | only after a Bash call **fails** |

Together they cover every command that actually ran. A failed command is often the one you most
want to find later, so recording only successes would be the wrong half.

**`PreToolUse` is deliberately not used.** It fires *before* the permission prompt, so it would
record commands you then declined — commands that never ran.

## Verifying

Pipe a synthetic payload straight into the recorder:

```bash
echo '{"hook_event_name":"PostToolUse","session_id":"test","cwd":"/tmp","tool_name":"Bash","tool_input":{"command":"echo probe"}}' \
  | ~/.config/shared-terminal-history/record-command --source claude-code --debug
tail -2 ~/.bash_history
```

Then end to end: ask Claude to run any command, and check it landed.

```bash
shared-history agents 5
```

Editing `~/.claude/settings.json` takes effect in running sessions without a restart (confirmed
in 2.1.211). If it ever does not, open `/hooks` once in Claude Code to force a config reload.

## Troubleshooting

**Nothing is recorded.** Confirm the hook is registered and the path is absolute and executable:

```bash
jq '.hooks' ~/.claude/settings.json
ls -l ~/.config/shared-terminal-history/record-command
```

**Claude reports a hook error.** The hook must print nothing to stdout — on exit 0 Claude Code
parses stdout as a JSON control document. If you have edited `record-command`, make sure every
diagnostic goes to a file or to stderr behind `--debug`.

**Subagent commands.** Hooks fire for subagents too; their entries carry the agent type in the
audit log.
