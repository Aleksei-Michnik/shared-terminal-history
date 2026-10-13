# shared-terminal-history

One bash history, shared live across every terminal you have open — **including the
non-interactive shells your coding agents run commands in.**

Open five terminals and a Claude Code session. Every command any of them runs lands in the
same history, and every terminal picks it up at its next prompt. Nothing to restart, nothing
to merge.

```
terminal 1  ─┐
terminal 2  ─┤
terminal 3  ─┼──►  ~/.bash_history  ◄── reloaded by every terminal at every prompt
Claude Code ─┤
your agent  ─┘
```

- **Store:** `~/.bash_history` — plain bash format, no database, no daemon
- **Default cap:** 19999 commands
- **Refresh point:** every prompt, in every terminal

---

## Why this is not just `shopt -s histappend`

Two problems that the usual snippets get wrong.

**1. `history -n` loses commands.** The common advice is
`PROMPT_COMMAND='history -a; history -n'`. `history -n` reads "lines added since I last read"
by tracking a line-count offset. When another terminal appends between two of your commands
that offset goes stale, and entries are dropped. Reproduced while building this:

```
in-memory list after another terminal appended a line
  1  echo AAA_from_session_A
  2  printf ... >> $HISTFILE          <- the externally appended line should be here
  3  printf ... >> $HISTFILE          <- instead: entry 2 duplicated, external line lost
```

This project uses `history -a; history -c; history -r` — flush, drop, reload the whole file.
Always correct, and a few milliseconds at the default cap.

**2. Agents are invisible to your shell config.** A coding agent runs each command as a
non-interactive `bash -c`. Check it yourself:

```bash
$ echo $-
himBHs        # interactive: has "i"
# inside an agent's shell:
hmtBc         # no "i" — ~/.bashrc is never sourced, and no history is kept at all
```

No `.bashrc`, `.bash_profile` or `.inputrc` change can capture those commands. They have to
be captured at the agent's own hook layer, which is what [`agents/`](agents/) is for.

---

## Install

Requires **bash 4.4+** (5.1+ recommended), plus `jq` and `flock` for the agent hooks.
Linux, WSL2 and macOS (with a modern bash from Homebrew).

```bash
git clone https://github.com/Aleksei-Michnik/shared-terminal-history.git
cd shared-terminal-history
./install.sh
```

The installer:

1. copies `shell-init.bash` and `record-command` into `~/.config/shared-terminal-history/`,
   and `shared-history` into `~/.local/bin/`
2. appends a source block to the **end** of `~/.bashrc` (backing it up first)
3. comments out any `HISTFILESIZE=<number>` line elsewhere in `~/.bashrc` — see
   [the cap](#what-gets-set-and-why) — and reports any `PROMPT_COMMAND` running its own
   `history -a`
4. detects installed agents and offers to wire them up

Then open a new terminal and check:

```bash
shared-history status
```

Options: `./install.sh --max 50000` for a different cap, `--no-agents` to skip agent wiring.
Re-running is safe — it upgrades in place and never clobbers your config file.

To remove everything (your history file is left alone, and the lines the installer commented
out come back): `./uninstall.sh`

---

## The one thing to know

**A terminal refreshes when it draws a prompt — not while you are sitting at one.**

If terminal B has been idle at a prompt and you run something in terminal A, B's Up-arrow will
not show it yet: B's list was loaded when B's prompt was drawn, which was before A ran anything.

**Press Enter on an empty line.** That draws a new prompt, which syncs. Everything from every
terminal and every agent is then one Up-arrow away.

That is the only manual step in the whole design, and only when you have been sitting at an
untouched prompt.

---

## Usage

```bash
shared-history status          # where it lives, how full, whether the wiring is intact
shared-history tail 40         # last 40 commands from any terminal, with timestamps
shared-history search docker   # case-insensitive grep, oldest first, with timestamps
shared-history agents 20       # last 20 commands your agents ran, with working directory
shared-history trim            # enforce the cap on the history and the audit log now
shared-history doctor          # check every part of the setup
```

Inside a terminal everything works as always — `history`, Up-arrow, `Ctrl-R` — the list just
contains every terminal's commands now.

**To keep a command out of the history, type a leading space.** `HISTCONTROL=ignorespace` is
set, so space-prefixed commands are never recorded. Use it for anything containing a secret.

---

## Agent support

| Agent | Status | Setup |
|---|---|---|
| [Claude Code](agents/claude-code.md) | Supported, wired automatically | `agents/install-claude-code.sh` |
| [Codex](agents/codex.md) | Not yet — contributions welcome | — |
| [OpenCode](agents/opencode.md) | Not yet — contributions welcome | — |
| [Kilo Code](agents/kilo-code.md) | Not yet — contributions welcome | — |

Adding an agent is usually a few lines of config. Every integration funnels into one script,
`record-command`, which accepts either a JSON hook payload on stdin or a literal command:

```bash
# JSON payload — the command is found automatically in the usual places
echo '{"tool_input":{"command":"npm test"},"cwd":"/srv/app"}' \
  | ~/.config/shared-terminal-history/record-command --source my-agent

# or pass it directly
~/.config/shared-terminal-history/record-command --source my-agent -- "npm test"
```

See [agents/README.md](agents/README.md) for the full contract and how to add one.

---

## Configuration

`~/.config/shared-terminal-history/config`, written once at install and never overwritten:

```bash
SHARED_HISTORY_MAX=19999  # commands the history and the audit log each keep; -1 for unlimited
# SHARED_HISTFILE="$HOME/.bash_history"
# SHARED_HISTORY_TIMEFORMAT='%F %T  '
```

### What gets set, and why

| Setting | Value | Why |
|---|---|---|
| `HISTSIZE` | `19999` | In-memory entries. Counts **commands**. |
| `HISTFILESIZE` | `39998` | File cap. Counts **lines** — and with timestamps every command is two lines (`#<epoch>` + the command), so it is 2 x the command cap. Verified on bash 5.1: `HISTFILESIZE=10` keeps exactly 5 timestamped commands. |
| `HISTTIMEFORMAT` | `'%F %T  '` | Required. Without it bash writes no `#<epoch>` lines, and entries from other terminals could not be dated or ordered. |
| `HISTCONTROL` | `ignorespace` | See below. |
| `histappend` | on | Never overwrite the shared file with one session's list. |
| `cmdhist` | on | A multi-line command becomes one history entry. |

**`ignoredups` is deliberately not set.** It suppresses a command matching the previous entry —
but with a shared history the "previous entry" is whatever *another terminal* ran last, so it
would silently discard real commands.

**The cap.** `HISTSIZE` bounds each terminal's in-memory list immediately. Bash truncates the
*file* whenever `HISTFILESIZE` is assigned — so at every new terminal — and again when a shell
exits; in between it can drift above the cap. Harmless, and it settles on its own.
`shared-history trim` enforces it immediately.

That truncation on assignment is why the installer comments out any `HISTFILESIZE=<number>`
line elsewhere in `~/.bashrc`. Ubuntu's stock `.bashrc` sets `HISTFILESIZE=2000` near its top,
and bash cuts the file to 2000 lines right there — at every new terminal, before the block at
the end can raise the cap. The commented lines carry a `# [shared-terminal-history]` prefix, and
`uninstall.sh` restores them. `HISTSIZE` lines need no such care: bash loads the history only
after `~/.bashrc` has run.

---

## Design notes

- **Multi-line agent commands** are folded onto one line with literal `\n` escapes. Writing raw
  lines would split one command into several independently recallable entries, and a fragment
  like `rm -rf "$dir"` recalled on its own is dangerous. Single-line commands are byte-exact,
  up to the length limit below. The unmodified command is kept in the audit log,
  `~/.local/share/shared-terminal-history/agent-commands.jsonl`, which holds the newest
  `SHARED_HISTORY_MAX` agent commands.
- **Agent commands over 4096 characters** — a heredoc that writes a whole file — are recorded
  as a `#` comment giving their length, followed by their first 200 characters. Every terminal
  reloads the whole history at every prompt, and a command cut short could still run when
  recalled; the comment cannot. The audit log keeps them in full.
- **Load order matters.** The `.bashrc` block goes last. Anything sourced after it that assigns
  `PROMPT_COMMAND=` (rather than appending) silently disables the sync.
- **Hooks must not write to stdout.** Agents parse a hook's stdout as a control document.
  `record-command` writes only to files, and always exits 0 so a logging failure can never
  disturb the agent.

## Limits

- **Plain scripts are not captured.** Only interactive terminals and wired-up agents are. A
  `#!/bin/bash` script's internal commands are not recorded — by design. Capturing them needs
  `BASH_ENV`, which makes *every* non-interactive bash source a file: a well-known way to break
  scripts, for a flood of history nobody wants.
- **Appends are best-effort under concurrency.** This project's writers serialise on `flock`;
  bash's own `history -a` does not take that lock. Bash appends with `O_APPEND` in a single
  write, so interleaving is very unlikely, but it is not a hard guarantee.
- **Secrets land in the history** unless you type a leading space. The history and the agent
  audit log are created `0600` (the audit log in a `0700` directory), but they are plain text.
- **Bash only.** Zsh and fish have their own sharing mechanisms and are not covered.

## Licence

MIT — see [LICENSE](LICENSE).
