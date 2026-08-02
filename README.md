# tmux-config

Personal tmux configuration, ported from [`zellij-config`](https://github.com/JoseAmador95/zellij-config).

Single terminal window, single tab: you switch between multiplexer **sessions** — local
per-project sessions and sessions dedicated to SSH hosts — instead of juggling terminal tabs.

## Why the move from Zellij

Two requirements were structurally impossible in Zellij and are native in tmux:

- **Never mix local and SSH.** In a Zellij `ssh_*` session a new *tab* entered the remote host but a
  pane *split* opened a **local** shell, because the `zellij-switch` plugin cannot set `default_shell`
  per session. In tmux, `default-command` is a **session option**: it applies to `new-window` **and**
  `split-window`, and it does not leak to other sessions.
- **Extend the personal config with a work config.** Zellij has no `include`. tmux composes configs
  with `source-file -q`.

## Install

```sh
git clone <your-fork> ~/.config/tmux
~/.config/tmux/bootstrap.sh
```

`bootstrap.sh` is idempotent and downloads nothing. It checks `tmux >= 3.4`, marks the scripts
executable, and wires `source ~/.config/tmux/shell/functions.sh` into your rc (`~/.config/sh/rc.sh`,
else `~/.zshrc`/`~/.bashrc`) inside a `# >>> tmux-functions >>>` block. tmux auto-loads
`~/.config/tmux/tmux.conf`, so the config itself needs no wiring. It coexists with an existing
Zellij install (separate servers).

Requires **tmux ≥ 3.4**. Optional: `fzf` (for the `Alt-Space` command palette).

## Usage

| Command | What it does |
|---|---|
| `t` / `t <name>` | attach/create the `main` session (or `<name>`) |
| `tcwd` | session rooted in the current directory, with the `dev` layout (`agent · editor · git · term`) |
| `tssh <host>` | dedicated SSH session `ssh_<host>`; every pane/window enters the host |
| `tcopy` | copy the current pane's full scrollback to the clipboard |
| `agent` | run this host's AI agent (see below) |

The `dev` layout's **agent** window resolves its command from `$TMUX_AGENT`, else the first useful
line of `~/.config/tmux/agent.local`, else a shell with a warning. Per host:
`export TMUX_AGENT=codex` or `echo codex > ~/.config/tmux/agent.local`.

### Keys (prefix is `Ctrl-a`)

| Key | Action |
|---|---|
| `Alt-h/j/k/l` | move between panes (forwarded to nvim inside a vim pane) |
| `Alt-n` / `Alt-t` | split pane / new window |
| `Alt-1`…`Alt-9` | select window |
| `Alt-,` / `Alt-.` | previous / next session |
| `Alt-s` | visual session tree (keyboard + mouse) |
| `prefix + Tab` | last session (toggle) |
| `prefix + 1`…`9` | jump to the N-th session in the bar |
| `prefix + H/J/K/L` | resize pane (repeatable) |
| `prefix + r` | reload `tmux.conf` |

## The SSH shield

Two layers guarantee that a pane in an `ssh_<host>` session can never silently fall back to a local
shell:

1. `tssh <host>` creates the session's first pane already running
   `scripts/ssh-host.sh <host>` (`exec ssh -t <host>`).
2. The `session-created` hook runs `scripts/session-created.sh`, which sets a per-session
   `default-command` for **any** `ssh_*` session — however it was created (`tssh`, `tmux new`,
   `choose-tree`, a sourced file). So new windows and splits also re-enter the host.

`ssh-host.sh` takes the host as an argument; with no host it opens a **local** shell and **never**
SSHes.

**Escape routes (cannot be fully shielded — know these):**

- An explicit command wins over `default-command`: `split-window htop` runs `htop` locally.
- `join-pane` / `move-pane` bring a pane whose process is **already running** from another session.
- Never set `default-command` with `set -g` — it would make every local session try to SSH.

## Work / per-machine config

At the end of `tmux.conf`:

```tmux
source-file -q ~/.config/tmux-work/work.conf   # private (company) repo, cloned separately
source-file -q ~/.config/tmux/local.conf       # per-machine, gitignored
```

`-q` is silent when the file is absent. The work layer may override global options, styles, and add
its own bindings; use `%if`/`%elif`/`%endif` for host/OS conditionals (parse-time, no subshell).

## Neovim interplay

- `Alt-hjkl` are `is_vim`-guarded so [smart-splits](https://github.com/mrjones2014/smart-splits.nvim)
  keeps navigating nvim splits and hands off to neighbouring tmux panes at the edge. Set
  `multiplexer_integration = "tmux"` in nvim.
- `set-clipboard on` lets nvim's OSC 52 (yanking over SSH) reach the local clipboard.
- `focus-events on` makes nvim's `FocusGained → checktime` autocmd fire.
- Known regressions under tmux: nvim's OSC 11 light/dark auto-detection may need a pin in
  `~/.nvim-local.lua`; Kitty-graphics image/diagram previews do not survive tmux reliably.

## What is lost vs. Zellij

Declarative nested layouts; session persistence across a **reboot** (sessions still survive closing
the terminal and SSH drops); rounded pane-frame corners; and — inside nvim — Kitty-graphics previews.
Accepted trade-offs.

## Development

POSIX `sh` with `set -u`, `sh -n` clean; Conventional Commits in English; see `AGENTS.md`. Never
push to `main` without testing the phase on the target machine. Test on an isolated socket
(`tmux -L smoke`), never the running server.
