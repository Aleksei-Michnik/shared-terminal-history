# Agent integrations

A coding agent runs each shell command as a non-interactive `bash -c`. That shell never sources
`~/.bashrc` and keeps no history of its own, so no shell configuration can capture it. Each
agent has to be hooked at its own layer.

| Agent | Status | Notes |
|---|---|---|
| [Claude Code](claude-code.md) | Supported | `install-claude-code.sh`, wired by `install.sh` |
| [Codex](codex.md) | Wanted | Needs a verified command-execution hook |
| [OpenCode](opencode.md) | Wanted | Needs a verified command-execution hook |
| [Kilo Code](kilo-code.md) | Wanted | VS Code extension; hook mechanism unverified |

## The contract

Every integration funnels into one script, so adding an agent is config, not code:

```
~/.config/shared-terminal-history/record-command [options] [-- COMMAND...]
```

| Option | Meaning |
|---|---|
| `--source NAME` | Label stored in the audit log. Use the agent's name. |
| `--field PATH`  | `jq` path to the command inside a JSON payload. Repeatable. |
| `--cwd DIR`     | Working directory for the audit log. Defaults to the payload's `.cwd`, else `$PWD`. |

Input, in order of preference:

```bash
# 1. JSON on stdin — the command is looked up in the usual places:
#    .tool_input.command, .command, .input.command, .args.command,
#    .params.command, .tool_input.cmd
echo '{"tool_input":{"command":"npm test"},"cwd":"/srv/app"}' | record-command --source my-agent

# 2. JSON on stdin with a non-standard shape
echo '{"exec":{"cmdline":"npm test"}}' | record-command --source my-agent --field '.exec.cmdline'

# 3. The command as an argument
record-command --source my-agent --cwd /srv/app -- "npm test"

# 4. Raw (non-JSON) text on stdin
echo 'npm test' | record-command --source my-agent
```

`--debug` reports to stderr what was matched and recorded.

## Rules any integration must follow

1. **Write nothing to stdout.** Agents parse a hook's stdout as a control document; stray output
   can block or confuse the tool call. `record-command` already obeys this — keep it that way.
2. **Always exit 0.** A logging failure must never disturb the agent. Many agents treat a
   non-zero hook as a blocking error.
3. **Hook the *post*-execution event, not the pre-execution one** — if the agent distinguishes
   them. A pre-execution hook usually fires before the user approves the command, so it records
   commands that never ran. If the agent has separate success and failure events, wire **both**.
4. **Be idempotent.** Installing twice must not produce two entries.

## Adding an agent

1. Find the agent's hook or notification mechanism, and the payload it provides.
2. Confirm the payload actually contains the command text and, ideally, the working directory.
3. Pipe-test before wiring anything up:
   ```bash
   echo '<a real payload>' | ~/.config/shared-terminal-history/record-command --source NAME --debug
   tail -2 ~/.bash_history
   ```
4. Add `agents/<name>.md` describing the setup, and `agents/install-<name>.sh` if it can be
   automated. Follow `install-claude-code.sh`: back up the config, refuse to touch invalid
   config, drop any previous entry of ours before appending.
5. Add it to the table above and in the root `README.md`, and teach `shared-history doctor`
   to report it.

Verified integrations only, please — a documented hook that turns out not to exist is worse
than an honest "not yet".
