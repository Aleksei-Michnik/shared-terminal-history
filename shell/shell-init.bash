# shared-terminal-history: one bash history, shared live across every terminal.
#
# Sourced from the very END of ~/.bashrc — after anything else that may set
# PROMPT_COMMAND (nvm, starship, direnv, ...), or that would drop the sync.
#
# Interactive shells only. Non-interactive shells (plain scripts, and the `bash -c`
# that coding agents run commands in) never source ~/.bashrc, so agent commands are
# captured separately by hooks/record-command. See agents/ for per-agent setup.

# Only interactive shells.
case $- in
    *i*) ;;
      *) return 0 ;;
esac

# Idempotent: sourcing ~/.bashrc twice must not stack PROMPT_COMMAND entries.
[ -n "${__SHARED_HISTORY_LOADED:-}" ] && return 0
__SHARED_HISTORY_LOADED=1

# Optional overrides, e.g. SHARED_HISTORY_MAX=50000. Config file wins over defaults,
# environment wins over the config file.
if [ -r "${SHARED_HISTORY_CONFIG:-$HOME/.config/shared-terminal-history/config}" ]; then
    . "${SHARED_HISTORY_CONFIG:-$HOME/.config/shared-terminal-history/config}"
fi

# The single shared store. Every terminal, and every agent hook, appends here.
export HISTFILE="${SHARED_HISTFILE:-$HOME/.bash_history}"

# How many commands to keep. Anything non-numeric falls back to the default.
: "${SHARED_HISTORY_MAX:=19999}"
case $SHARED_HISTORY_MAX in
    -1|[0-9]*) ;;
    *) SHARED_HISTORY_MAX=19999 ;;
esac

# HISTSIZE counts entries. HISTFILESIZE counts *lines*, and because HISTTIMEFORMAT
# is set below, every command occupies two lines (`#<epoch>` + the command) — so the
# file cap is twice the command cap. Verified on bash 5.1: HISTFILESIZE=10 keeps
# exactly 5 timestamped commands.
# Set SHARED_HISTORY_MAX=-1 for unlimited (expect slower prompts once the file grows
# into the hundreds of thousands of lines).
HISTSIZE=$SHARED_HISTORY_MAX
if [ "$SHARED_HISTORY_MAX" = "-1" ]; then
    HISTFILESIZE=-1
else
    HISTFILESIZE=$((SHARED_HISTORY_MAX * 2))
fi

# Required. Without HISTTIMEFORMAT bash writes no `#<epoch>` lines, and entries
# arriving from other terminals could not be dated or ordered.
HISTTIMEFORMAT="${SHARED_HISTORY_TIMEFORMAT:-%F %T  }"

# `ignoredups` is deliberately NOT set. With a shared history the "previous entry" is
# whatever another terminal ran last, so ignoredups would silently drop real commands.
# `ignorespace` is kept: a leading space still means "do not record this one".
HISTCONTROL=ignorespace

shopt -s histappend     # never overwrite the shared file with one session's list
shopt -s cmdhist        # a multi-line command becomes a single history entry
shopt -u lithist

# Runs at every prompt:
#   history -a  flush this shell's new commands to the shared file
#   history -c  drop the in-memory list
#   history -r  reload the whole shared file
#
# The -c/-r pair rather than the cheaper `history -n` is required for correctness:
# `history -n` tracks its read offset by line count, and when another writer appends
# between two of this shell's commands that offset goes stale and entries are lost.
__shared_history_sync() {
    local __sh_status=$?
    history -a
    history -c
    history -r
    return $__sh_status
}

# Prepend, preserving anything that already owns PROMPT_COMMAND.
#
# Since bash 5.1 PROMPT_COMMAND may be an array, and ${var@a} reports attribute flags
# so an "a" among them means array. ${var@a} itself only exists in bash 4.4+, so the
# version test guards it — && short-circuits before the expansion is evaluated, which
# keeps this file safe to source on older bash (e.g. the 3.2 macOS ships).
if ((BASH_VERSINFO[0] > 5 || (BASH_VERSINFO[0] == 5 && BASH_VERSINFO[1] >= 1))) &&
   [[ ${PROMPT_COMMAND@a} == *a* ]]; then
    PROMPT_COMMAND=(__shared_history_sync "${PROMPT_COMMAND[@]}")
else
    PROMPT_COMMAND="__shared_history_sync${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
fi
