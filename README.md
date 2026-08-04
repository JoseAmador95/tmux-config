# tmux-config

Personal tmux configuration, ported from [`zellij-config`](https://github.com/JoseAmador95/zellij-config).

Single terminal window, single tab: you switch between multiplexer **sessions** — local
per-project sessions and sessions dedicated to SSH hosts — instead of juggling terminal tabs.

## Why the move from Zellij

Two requirements were structurally impossible in Zellij and are native in tmux:

- **Never mix local and SSH.** In a Zellij `ssh_*` session a new _tab_ entered the remote host but a
  pane _split_ opened a **local** shell, because the `zellij-switch` plugin cannot set `default_shell`
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

Requires **tmux ≥ 3.4** and **`fzf` ≥ 0.59** — `fzf` is not optional: `Alt-s`, `Alt-Space` and
`prefix + ?` are all fzf popups and there is no fallback. Below 0.59 everything still works except
that `Esc` leaves the session popup's `/` search by closing the popup instead of returning to the
action keys.

The status bar uses **Nerd Font** glyphs (pill caps and one icon per window) and therefore needs a
**UTF-8 locale**: with `LC_CTYPE=POSIX` tmux silently drops those characters and the pills lose
their rounded ends.

## Usage

| Command          | What it does                                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------------------------------- |
| `t` / `t <name>` | attach/create the `main` session (or `<name>`)                                                                        |
| `tp [dir]`       | session with the `dev` layout (`agent · editor · git · term`), rooted in `dir` (default: cwd). `tcwd` is a kept alias |
| `tssh <host>`    | dedicated SSH session `ssh_<host>`; every pane/window enters the host                                                 |
| `tcopy`          | copy the current pane's full scrollback to the clipboard                                                              |
| `agent`          | run this host's AI agent (see below)                                                                                  |

The `dev` layout's **agent** window resolves its command from `$TMUX_AGENT`, else the first useful
line of `~/.config/tmux/agent.local`, else a shell with a warning. Per host:
`export TMUX_AGENT=codex` or `echo codex > ~/.config/tmux/agent.local`.

### Keys (prefix is `Ctrl-a`, or `Ctrl-Space` as a secondary leader)

| Key                | Action                                                        |
| ------------------ | ------------------------------------------------------------- |
| `Alt-h/j/k/l`      | move between panes (forwarded to nvim inside a vim pane)      |
| `Alt-n` / `Alt-t`  | split pane / new window                                       |
| `Alt-1`…`Alt-9`    | select window                                                 |
| `Alt-←` / `Alt-→`  | previous / next window (tab)                                  |
| `Alt-,` / `Alt-.`  | previous / next session                                       |
| `Alt-s`            | session manager popup (below); clicking the session strip too |
| `Alt-Space`        | command palette                                               |
| `Alt-v`            | enter copy mode                                               |
| `prefix + Tab`     | last session (toggle)                                         |
| `prefix + 1`…`9`   | jump to the N-th session in the bar                           |
| `prefix + H/J/K/L` | resize pane (repeatable)                                      |
| `prefix + R`       | respawn a dead pane (revive a closed dev-layout tool window)  |
| `prefix + r`       | reload `tmux.conf`                                            |
| `prefix + ?`       | searchable cheatsheet of these bindings                       |
| `prefix + e`       | grab a path/URL/token off the screen into the command line    |
| `prefix + F`       | fuzzy-search the scrollback and jump to the hit               |
| `prefix + u`       | pick a URL from the pane and open it                          |
| `prefix + @`       | promote this pane to a session of its own                     |
| `prefix + <` / `>` | move this window left / right in the list                     |
| `prefix + P`       | start/stop writing this pane to a log file                    |
| `prefix + N`       | alert me when this window goes quiet                          |
| `F12`              | OFF mode — all tmux keys off, for a tmux inside this one      |

### The session manager (`Alt-s`)

Two modes, like vim, because type-to-filter and single-letter actions cannot share a keyboard:

| Mode                  | Keys                                                                                                                                                                |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **actions** (default) | `1`…`9` jump + switch · `j`/`k` move · `g`/`G` ends · `r` rename · `n` new · `x` kill · `s` classic `choose-tree` · `Enter` / double-click switch · `q`/`Esc` close |
| **search** (`/`)      | type to filter · `Enter` switch · `Esc` back to the action keys                                                                                                     |

`r`, `n` and `x` open a prompt that **`Esc` cancels**; `x` confirms with the cursor parked on `no`.
Leaving search clears the filter, so the digits always address the full list — the same order as
`prefix + <digit>` and the numbers on the status bar.

**Closing it with the mouse:** a left-click outside the popup does not close it, and cannot be made
to. tmux's `popup_key_cb` returns "keep open" for out-of-bounds mouse events in every version from
3.4 to master _and_ swallows the click, so fzf never receives it and `--no-mouse` changes nothing.
Use `q` / `Esc`, or the mouse gesture tmux does offer: **right-press outside, drag onto `Close`,
release** (tmux's own popup menu, ≥ 3.3). A right click-and-release in place only opens and closes
that menu again — it is a drag, not a click.

## The status bar

**Catppuccin**, on a white terminal. The bar paints no background of its own (`bg=terminal`), so it
takes Ghostty's, and the accent — Latte `blue #1e66f5` — lives only in the pills.

Every tab is **two chips**: the accent holds the index, the name sits on a neutral chip, and each
cap takes the colour of the chip it terminates. That edge inside one object is what stops the
accent reading as a slab — it is the shape Catppuccin itself uses. Inactive tabs get a quiet card
instead of floating on the bar.

All four flavours ship. `scripts/theme.sh` owns the palette, the semantic roles and the per-host
tints; **switching is one option and a re-run**, from the `Alt-Space` palette or by hand:

```tmux
:set -g @thm_flavor mocha ; run-shell "~/.config/tmux/scripts/theme.sh"
```

The pill text is _measured_, not written down. Every pill is text-on-colour, and the right
foreground flips both with the flavour and within it — white reads on Latte's blue (4.91:1) and not
on Mocha's (2.10:1), and inside Latte it reads on blue but not on yellow (2.62:1). `theme.sh`
computes each one, so a palette edit cannot silently produce an illegible pill. All 56 pairings
across the four flavours measure ≥ 4.5:1.

Three places deliberately depart from upstream `catppuccin/tmux`, all for legibility — which
Catppuccin's own style guide asks for over fidelity. Pill text is `#ffffff`, not `crust`, because
crust on an accent clears 4.5:1 on _no_ Latte accent (upstream's own default mauve pill is 4.09:1).
Inactive pane borders use `overlay1`, not `overlay0`, which on white is 2.60:1 and fails even the
3:1 UI threshold. And `message-style` is white on the accent rather than upstream's teal on
`overlay0`, which is 1.44:1.

- **left** — empty for a local session. An `ssh_<host>` session shows its **host** here instead, in
  that host's own stable tint, so a remote session can never be mistaken for a local one.
- **centre** — the window list, anchored with `status-justify absolute-centre` so the tabs do not
  slide when the session name changes length. Each window carries an icon for what is running in it.
- **right** — the current mode (prefix / copy-mode / zoom / synchronized), then the numbered session
  strip that `prefix + <digit>` jumps to. The session you are on is the two-chip pill in it, and
  clicking the strip opens the session manager.

Nothing on the bar shells out — there is no `#()` anywhere. The reason is not the one you would
guess, so it is worth stating precisely: tmux caches a `#()` and re-runs it on the `status-interval`
timer, not on every redraw. Measured with 6 windows, at `status-interval 5`, that is 6 forks every
5s; ordinary redraws reuse the cache. But this config sets **`status-interval 0`**, so a `#()` would
run **once** and then show the same value for the life of the client. The problem with a `#()` here
is staleness, not cost — which is exactly why every status module (battery, cpu, gitmux) forces the
timer on, and why none of them fit a bar whose `status-right` is the session strip.

In copy mode (`prefix + [` or scroll up): `v` select, `y` / `Enter` / `Ctrl-C` / mouse-drag-release copy
**without** leaving copy mode (the selection also reaches the system clipboard); `q` / `Esc` to exit.
The `dev` tool windows (`agent · editor · git`) stay put when their app exits — the pane goes _dead_
instead of the window closing, so `prefix + R` relaunches it (`term` stays a disposable shell).

## Sessions survive a reboot

The session hooks keep a roster at `${XDG_STATE_HOME:-~/.local/state}/tmux/roster` — each session's
name, directory and a window signature. The first `t` after a boot replays it.

It restores _which projects were open_, not their exact contents, and that is the whole design:
these sessions are reproducible by construction, so a name and a path are enough. A session whose
signature says it came from `tp` is rebuilt through `sessions/dev.conf`, so its four tool windows
come back rather than a bare shell.

**`ssh_*` sessions are saved but never auto-restored.** Recreating one arms the SSH shield's
`default-command`, so every pane it opens dials out at once — a boot would fire N ssh connections
at possibly-down hosts, maybe with N 2FA prompts, before you had typed anything. They are listed
instead; `tssh <host>` is one keystroke.

This is not tmux-resurrect and does not try to be: no pane geometry, no guessing at argv from `ps`,
no whitelist. Nothing is polled either — tmux-continuum's timer drives its save from the status
redraw, which needs `status-interval > 0` and an untouched `status-right`, and this config has
neither.

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
