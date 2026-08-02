# Shell functions for the tmux workflow. SOURCED from your rc (wired by bootstrap.sh).
# Reproducible: lives in the repo (~/.config/tmux/shell/), not loose in the rc.
# No shebang on purpose: this is for `source`, not execution.
#
# OPT-IN MODEL: tmux does not auto-start. You enter by hand with `t` / `tcwd` / `tssh`.
# So, with SSH and tmux on both hosts, the chain has a SINGLE tmux and `ssh` never nests
# (the remote runs only the client — a flat remote shell).

# ── File-descriptor limit ─────────────────────────────────────────────────────
# macOS ships a soft limit of 256 (`launchctl limit maxfiles`), inherited by Ghostty and every
# shell you open inside it. The tmux server inherits the limit of the shell that starts it, and
# 256 is NOT enough for a session with several panes: each pane is a pty. When they run out, the
# whole server dies with an "Os { code: 24, Too many open files }" error.
#
# It is not a leak: it is a too-low ceiling. The hard limit is `unlimited`, so raising the soft
# limit needs no sudo. This only RAISES (never lowers) and caps at the system hard limit (which
# on Linux may be finite).
#
# NOTE: only affects NEW servers. A live session keeps the limit it was born with; to apply this
# you must close and recreate it.
_t_raise_nofile() {
  local want=8192 cur hard
  cur=$(ulimit -Sn 2>/dev/null) || return 0
  [ "$cur" = unlimited ] && return 0
  [ "$cur" -ge "$want" ] 2>/dev/null && return 0
  hard=$(ulimit -Hn 2>/dev/null)
  if [ -n "$hard" ] && [ "$hard" != unlimited ] && [ "$hard" -lt "$want" ] 2>/dev/null; then
    want="$hard"
  fi
  ulimit -Sn "$want" 2>/dev/null || true
}
_t_raise_nofile
unset -f _t_raise_nofile 2>/dev/null

# t — attach or create the "main" session. Main command. `t` → "main"; `t foo` → "foo".
# tmux has no session serialization, so there is nothing to disable.
t() {
  local s="${1:-main}"
  tmux has-session -t "=$s" 2>/dev/null || tmux new-session -d -s "$s"
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$s"; else tmux attach -t "=$s"; fi
}

# tp [dir] — create (or jump to) a project session with the `dev` layout, rooted in `dir`
# (default: the CURRENT directory). Name = basename of the dir with dots → underscores (tmux
# forbids '.' and ':' in session names). The layout is built once (see sessions/dev.conf);
# afterwards we just switch/attach. Formerly `tcwd`, kept as an alias below.
tp() {
  local DIR="${1:-$PWD}"
  DIR=$(cd "$DIR" 2>/dev/null && pwd) || { echo "tp: not a directory: ${1:-$PWD}" >&2; return 1; }
  local SESS="${DIR##*/}"; SESS="${SESS//./_}"
  tmux has-session -t "=$SESS" 2>/dev/null || . "$HOME/.config/tmux/sessions/dev.conf"
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$SESS"; else tmux attach -t "=$SESS"; fi
}
tcwd() { tp "$@"; }   # backwards-compatible alias (name kept for muscle memory)

# tssh <host> — dedicated session for an SSH host: every pane/window enters the host.
# Name = "ssh_" + host sanitized ([^A-Za-z0-9_-] → _). The first pane enters via ssh-host.sh;
# the session-created hook then marks the session so new windows/splits also re-enter the host.
# Per-host options (user, port, -A) belong in ~/.ssh/config, not here.
tssh() {
  [ -n "${1:-}" ] || { echo "usage: tssh <host|~/.ssh/config alias>"; return 1; }
  local host="$1" sess="ssh_${1//[^A-Za-z0-9_-]/_}"
  local sh="$HOME/.config/tmux/scripts/ssh-host.sh"
  tmux has-session -t "=$sess" 2>/dev/null || tmux new-session -d -s "$sess" "$sh $host"
  if [ -n "${TMUX:-}" ]; then tmux switch-client -t "=$sess"; else tmux attach -t "=$sess"; fi
}

# ── tssh completion: Tab-complete the Host aliases from ~/.ssh/config ───────────────────
# Offers the `Host` aliases as candidates (you can still type any raw user@host). Skips wildcard/
# negated patterns. Reads only the main config — does not follow `Include`.
_t_ssh_hosts() {
  local cfg="$HOME/.ssh/config"
  [ -r "$cfg" ] || return 0
  awk 'tolower($1)=="host"{for(i=2;i<=NF;i++)if($i!~/[*?!]/)print $i}' "$cfg"
}
if [ -n "${ZSH_VERSION:-}" ]; then
  if whence compdef >/dev/null 2>&1; then
    _tssh() { local -a h; h=(${(f)"$(_t_ssh_hosts)"}); compadd -a h; }
    compdef _tssh tssh
  else
    _t_ssh_cc() { reply=(${(f)"$(_t_ssh_hosts)"}); }
    compctl -K _t_ssh_cc tssh
  fi
elif [ -n "${BASH_VERSION:-}" ]; then
  _t_ssh_bash() { local cur=${COMP_WORDS[COMP_CWORD]}; COMPREPLY=($(compgen -W "$(_t_ssh_hosts)" -- "$cur")); }
  complete -F _t_ssh_bash tssh
fi


# agent — launch THIS host's AI agent (claude/codex/…). Same resolver the `dev` layout uses.
# Per-host config: `export TMUX_AGENT=<cmd>` or `echo <cmd> > ~/.config/tmux/agent.local`.
agent() { "$HOME/.config/tmux/scripts/agent.sh"; }

# tcopy — copy the CURRENT pane's full scrollback to the clipboard (also bound to prefix + y).
# capture-pane's scrollback (-S -) piped to load-buffer -w, which pushes it out via OSC 52.
tcopy() {
  [ -n "${TMUX:-}" ] || { echo "tcopy: not inside tmux" >&2; return 1; }
  tmux capture-pane -pJS - -t "${TMUX_PANE}" | tmux load-buffer -w -
  echo "tcopy: scrollback copied to the clipboard"
}

# ── OSC 133 semantic prompts (so `prefix + Y` can copy only the last output) ────────────────
# tmux (>=3.4) moves between prompts with previous-prompt/next-prompt ONLY if the shell marks
# where the prompt (OSC 133;A) and the output (OSC 133;C) begin. We emit them from zsh inside
# tmux; the `prefix + Y` binding (tmux.conf) uses these marks. If your terminal (e.g. Ghostty)
# already emits OSC 133, export T_NO_OSC133=1 to avoid duplicate marks.
if [ -n "${ZSH_VERSION:-}" ] && [ -n "${TMUX:-}" ] && [ -z "${T_NO_OSC133:-}" ]; then
  _t_osc133_precmd()  { printf '\033]133;A\033\\'; }   # prompt start
  _t_osc133_preexec() { printf '\033]133;C\033\\'; }   # command output start
  autoload -Uz add-zsh-hook 2>/dev/null && {
    add-zsh-hook precmd  _t_osc133_precmd
    add-zsh-hook preexec _t_osc133_preexec
  }
fi
