# OpenCode

**Status:** not yet supported. Contributions welcome.

OpenCode runs shell commands the same way every agent does — through a non-interactive
`bash -c` that never sources `~/.bashrc` — so its commands are invisible to the shell-level
sharing until it is hooked at its own layer.

Upstream: https://github.com/sst/opencode

## What is needed

This integration is unwritten because its hook mechanism has not been **verified** by anyone
working on this project. Documenting a hook that turns out not to exist is worse than an honest
"not yet", so nothing is guessed here.

To contribute one, find out:

1. **Does it have a hook, event or notification mechanism** that fires around shell command
   execution? Check its config file, its docs, and any `hooks`/`notify`/`events` settings.
2. **Does the payload contain the command text?** The working directory too, ideally.
3. **Is there a post-execution event**, separate from a pre-approval one? Prefer post — a
   pre-execution hook records commands the user then declines.

Then follow the checklist in [README.md](README.md#adding-an-agent) and pipe-test with:

```bash
echo '<a real payload>' | ~/.config/shared-terminal-history/record-command --source opencode --debug
tail -2 ~/.bash_history
```

## Fallback that works without any hook support

If the agent lets you configure **which shell** it invokes, point it at a wrapper that records
and then executes. This works for any agent, at the cost of one extra process per command:

```bash
#!/usr/bin/env bash
# ~/.local/bin/recording-bash — set the agent's shell to this
[ "${1:-}" = "-c" ] && \
    ~/.config/shared-terminal-history/record-command --source opencode -- "$2"
exec /bin/bash "$@"
```

```bash
chmod +x ~/.local/bin/recording-bash
```

Verify the agent really invokes it as `-c '<command>'` before relying on it; some pass a script
path instead, in which case record `$(cat "$2")`.
