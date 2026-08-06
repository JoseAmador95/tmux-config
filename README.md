# tmux-config

Personal tmux configuration, ported from [`zellij-config`](https://github.com/JoseAmador95/zellij-config).

One terminal window, one tab. You switch between multiplexer **sessions** — local per-project ones
and ones dedicated to SSH hosts — instead of juggling terminal tabs.

---

## Quick start

```sh
git clone --recurse-submodules <your-fork> ~/.config/tmux
~/.config/tmux/bootstrap.sh
exec $SHELL          # or `source` your rc
t                    # attach/create the "main" session
```

`--recurse-submodules` matters: the plugins live in `plugins/` as submodules. If you forgot it,
`bootstrap.sh` fetches them anyway.

The repo must end up at **`~/.config/tmux`** — that is what tmux auto-loads, and nothing wires it
up for you. `bootstrap.sh` warns if it is somewhere else.

**Prerequisites**, each of which has cost a debugging session:

| Need               | Why                                                                                                                                                       |
| ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **tmux ≥ 3.4**     | the floor; the config works throughout. Automatic light/dark plus modal scrollbar/copy-position styling need **3.6**; the tree-preview accent needs **3.7**. Older supported versions keep tmux's defaults for those optional surfaces. |
| **`fzf` ≥ 0.59**   | not optional — `Alt-Space`, `prefix + ?`, `prefix + e` and `prefix + u` are fzf popups, with no fallback. (`Alt-s` is tmux's own tree and needs nothing.) |
| **A Nerd Font**    | the bar's pill caps and per-window icons.                                                                                                                 |
| **A UTF-8 locale** | with `LC_CTYPE=POSIX` tmux silently drops the Nerd Font glyphs and the pills lose their rounded ends.                                                     |
| **Python 3.6+**    | `extrakto` (`prefix + e`) and `tmux-easy-motion`.                                                                                                         |

`bootstrap.sh` is idempotent — re-run it any time. It checks the versions, fetches the submodules,
marks the scripts executable and wires `shell/functions.sh` into your rc inside a
`# >>> tmux-functions >>>` block. It coexists with an existing Zellij install (separate servers).

**What you should see:** a status bar at the **top**, blank on the left, a centred window list where
each tab is a two-tone pill, and on the right a numbered strip of your open sessions.

---

## The model

There is one terminal window and one tab in it. Everything else is a tmux **session**, and sessions
are **named** — the name drives the session pill on the bar and the SSH shield. You move between
them with `Alt-,` / `Alt-.`, `Alt--` to toggle back to the last one, the `Alt-s` tree, or `Alt-0`
straight to `main`.

| Command          | What it does                                                                                                          |
| ---------------- | --------------------------------------------------------------------------------------------------------------------- |
| `t` / `t <name>` | attach/create the `main` session (or `<name>`)                                                                        |
| `tp [dir]`       | session with the `dev` layout (`agent · editor · git · term`), rooted in `dir` (default: cwd). `tcwd` is a kept alias |
| `tssh <host>`    | dedicated SSH session `ssh_<host>`; every pane and window enters the host                                             |
| `tcopy`          | copy the current pane's full scrollback to the clipboard                                                              |
| `agent`          | run this host's AI agent                                                                                              |

The `dev` layout's **agent** window resolves its command from `$TMUX_AGENT`, else the first useful
line of `~/.config/tmux/agent.local`, else a shell with a warning. Per host:
`export TMUX_AGENT=codex` or `echo codex > ~/.config/tmux/agent.local`.

---

## Features

- **A status bar that never shells out** — no `#()` anywhere, so nothing on it can hang or go
  stale. [Details](#the-status-bar).
- **tmux's own session tree** on `Alt-s` — instant, no modes, no dependency.
  [Details](#the-session-manager-alt-s).
- **Sessions survive a reboot** — a roster of names and paths, replayed by the first `t`.
  [Details](#sessions-survive-a-reboot).
- **The SSH shield** — a pane in an `ssh_<host>` session cannot silently fall back to a local
  shell. [Details](#the-ssh-shield).
- **Copy mode that does not fight you** — copying never leaves copy mode and never snaps to the
  bottom. [Details](#copy-mode).
- **Five plugins**, vendored as git submodules and pinned by SHA. [Details](#plugins).
- **Four Catppuccin flavours**, one option to switch, and on tmux 3.6+ it follows your terminal's
  light/dark theme by itself.

---

## Keys

Prefix is `Ctrl-a`, with `Ctrl-Space` as a secondary leader. `prefix + ?` shows this same list in a
searchable popup (`scripts/keys.sh`).

Only what this config defines is listed — tmux's own defaults still work. The **owner** column says
what to blame when a key misbehaves; a key owned by a plugin does nothing if that plugin was not
fetched.

### Sessions

| Key               | Action                                    | Owner  |
| ----------------- | ----------------------------------------- | ------ |
| `Alt-s`           | session tree (or click the session pill)  | config |
| `Alt-,` / `Alt-.` | previous / next session                   | config |
| `Alt--`           | last session (toggle)                     | config |
| `prefix + Tab`    | last session (toggle), same as `Alt--`    | config |
| `Alt-0`           | jump to `main`, always                    | config |
| `prefix + 0`      | jump to `main`, always — same as `Alt-0`  | config |
| `prefix + @`      | promote this pane to a session of its own | config |

**`Alt-0` / `prefix + 0` are unconditional**, both running the exact same command. They go straight
to the session literally named `main`, and say so instead of doing something else if that session
does not exist yet — neither creates one; `t` already does attach-or-create.

There used to be a `prefix + 1`…`9` too, jumping to the N-th session of a recency-based order. It
is gone: the order lived in a file nothing else needed once the bar stopped showing a numbered
strip and `Alt-s` got its own, different numbering, so a digit was memorised or looked up rather
than read off anything on screen — and a keybinding that only works memorised isn't much of one.
`Alt-,` / `Alt-.`, `Alt--`, `Alt-s` and `Alt-0` / `prefix + 0` are what is left to switch sessions
without typing a name.

### Windows

| Key                | Action                               | Owner  |
| ------------------ | ------------------------------------ | ------ |
| `Alt-t`            | new window, in the current dir       | config |
| `Alt-1`…`Alt-9`    | select window N                      | config |
| `Alt-;` / `Alt-'`  | previous / next window               | config |
| `prefix + <` / `>` | move this window left / right        | config |
| `prefix + N`       | alert me when this window goes quiet | config |

Each window tab shows at most one alert marker, with this priority: red `!` bell, yellow `◆`
silence, green `●` activity; **bell > silence > activity**. `prefix + N` arms silence monitoring
for the current window, so its yellow marker appears when that window goes quiet.

### Panes

| Key                | Action                                           | Owner  |
| ------------------ | ------------------------------------------------ | ------ |
| `Alt-h/j/k/l`      | move focus (forwarded to nvim inside a vim pane) | config |
| `Alt-n`            | split the longer axis (Zellij-like)              | config |
| `prefix + H/J/K/L` | resize (repeatable)                              | config |
| `prefix + R`       | respawn a dead pane                              | config |
| `prefix + P`       | start/stop logging this pane to a file           | config |

The line between two panes is `pane-border-lines heavy` — a bolder weight than tmux's thin default,
still a single glyph rather than a block, with `@thm_line` on top of it a shade more contrasting
than before (see [Contrast](#contrast)). Two heavier-handed attempts at this — blank-cell "padding"
that turned invisible without a matching background colour, then a same-colour-fg/bg solid bar that
fixed the visibility but lost the thin line entirely — were both tried and reverted in favour of this
smaller change.

Each live pane's frame (`pane-border-status top`) shows its index, the shared per-command `@wicon`,
the command, and the current directory's basename truncated to 20 characters. Two panes in the
same window can and do show different icons and commands because each pane's own
`#{pane_current_command}` drives the label; an `ssh` pane says `remote` instead of showing its
misleading local cwd. The active label is blue and bold. A dead pane replaces that context with its
exit status and `prefix + R` revive key.

### Copy & clipboard

| Key                                   | Action                                       | Owner     |
| ------------------------------------- | -------------------------------------------- | --------- |
| `Alt-i`                               | enter copy mode                              | config    |
| `v` / `y`                             | select / copy, **without leaving copy mode** | config    |
| `Enter`, `Ctrl-C`, mouse-drag-release | copy, same rule                              | config    |
| `d` / `u`                             | jump 10 lines down / up (vim's `10j`/`10k`)  | config    |
| `prefix + y`                          | copy the whole scrollback                    | config    |
| `prefix + Y`                          | copy only the last command's output          | config    |
| `o` / `C-o`                           | open the selection / open it in `$EDITOR`    | tmux-open |

### Find & grab

| Key          | Action                                                    | Owner            |
| ------------ | --------------------------------------------------------- | ---------------- |
| `prefix + e` | grab a path/URL/hash off the screen into the command line | extrakto         |
| `prefix + f` | label every match on screen; press its letter to copy     | tmux-fingers     |
| `Alt-f`      | same, no prefix                                           | tmux-fingers     |
| `prefix + F` | fuzzy-search the scrollback and jump to the hit           | tmux-fuzzback    |
| `prefix + u` | pick a URL from the pane and open it                      | config           |
| `U` / `O`    | (copy mode) jump back to the previous URL / file path     | config           |
| `s`          | (copy mode) easy-motion jump                              | tmux-easy-motion |

### General

| Key          | Action                                           | Owner  |
| ------------ | ------------------------------------------------ | ------ |
| `Alt-Space`  | command palette                                  | config |
| `prefix + ?` | this cheatsheet, searchable                      | config |
| `prefix + r` | reload `tmux.conf`                               | config |
| `F12`        | OFF mode — every tmux key off, for a nested tmux | config |

The `Alt-Space` palette also has a **show documentation** entry — it pages this same README in
place, inside the palette's own popup. Every other palette action is a curated tmux command
(`eval tmux …`); this one is the one exception, a `!`-prefixed raw shell command instead, because
`display-popup` cannot be nested — asked for one from inside another, tmux opens neither.

`prefix + f` is the only key here that replaces a tmux default (`find-window`). Everything else was
either free or already this config's.

---

## Plugins

Five, as git submodules under `plugins/`. **There is no plugin manager.** The submodule SHA is the
pin, it shows up in the diff, and `git clone --recurse-submodules` reproduces the exact set. TPM was
evaluated and rejected: its `#tag` pin is honoured on install only, changing one is a no-op,
`prefix + U` then fails on the resulting detached HEAD, and its own last substantive commit was in
February 2023 — while `brew install tpm`, the tidiest way to install it, is unavailable on Linux.

| Plugin             | What it gives you                                             | Needs               |
| ------------------ | ------------------------------------------------------------- | ------------------- |
| `tmux-fingers`     | hint letters painted over the screen (`prefix + f` / `Alt-f`) | a binary, see below |
| `tmux-fuzzback`    | scrollback search + jump (`prefix + F`)                       | fzf                 |
| `extrakto`         | grab tokens off the screen (`prefix + e`)                     | Python 3.6+, fzf    |
| `tmux-open`        | open the selection from copy mode (`o`)                       | `open` / `xdg-open` |
| `tmux-easy-motion` | easy-motion jumps in copy mode (`s`)                          | Python              |

Updating one is deliberate: `git submodule update --remote plugins/<name>`, then a commit that says
what moved.

**`tmux-fingers` is a compiled binary**, and prebuilt ones exist for **Linux x86_64 and macOS arm64
only**. Anywhere else, build it with Crystal or `brew install morantron/tmux-fingers/tmux-fingers`;
until then `prefix + f` and `Alt-f` both do nothing and everything else is unaffected. `bootstrap.sh`
fetches it, and `tmux.conf` refuses to load the plugin until the binary exists — its own loader would
otherwise fire a network installer in the background _every time the config is sourced_.

Three replaced hand-written code: `fuzzback.sh` and `grab.sh` were reimplementations of
`tmux-fuzzback` and `extrakto` and are gone. **`tmux-sessionist` was tried and rejected** — its
`promote_pane` creates _unnamed_ sessions, and it silently stole `prefix + C-Space`, the secondary
leader, because its promote-window default `C-@` is the same keystroke. `scripts/promote.sh` stays.

What deliberately stays hand-written: the theme (`catppuccin/tmux` measures 3/15 contrast segments
passing against our 14/14, and it opens by _unsetting_ the whole `@thm_*` namespace), the session
manager, and session persistence. Status modules — battery, cpu, gitmux, clima — cannot work here
at all: they need `status-interval > 0` and `status-right`, which the session strip owns.

---

## The session manager (`Alt-s`)

`Alt-s` opens **`choose-tree`, tmux's own session picker**. No modes, no filtering to escape from,
and no process spawned per keystroke.

On **tmux ≥ 3.7**, the tree's preview label uses the theme's blue accent. Older supported versions
keep tmux's default preview styling; the picker itself works unchanged.

| Key               |                                                                                  |
| ----------------- | -------------------------------------------------------------------------------- |
| `1`…`9`           | switch to that session immediately — the number is shown in brackets on the left |
| `j` / `k`, arrows | move · `Enter` chooses                                                           |
| `C-s`             | search by name · `n` / `N` repeat forwards / backwards                           |
| `x`               | kill the session (asks first) · `t` tags, `X` kills every tagged one             |
| `q` / `Esc`       | close                                                                            |

It replaced a hand-written fzf popup that implemented vim's `jj` to leave insert mode. fzf can only
express a two-key gesture as a `transform` running an external command, so **every `j` and `k` press
forked a shell and made three tmux round-trips just to answer "down" — 18 ms per keypress**, on the
two keys you navigate with. The native tree does the same job in-process.

**Rename and create are not in the tree** — they live in the `Alt-Space` palette (`rename session`,
`new session`), which is the one thing this trade cost.

**The numbering is choose-tree's own**, most-recently-used first (its `-O activity` sort — its `-O`
takes one of tmux's fixed names, and despite how it reads, `time` is not one of them). Nothing else
on the bar shows a competing order to disagree with any more — `prefix + <digit>` for 1-9 was
retired along with the file that used to define it. `Alt-0` / `prefix + 0` still always mean `main`,
but that is a fixed target, not a position in this tree's list.

**Closing a popup with the mouse** (`Alt-Space`, `prefix + ?`, `prefix + u` — `Alt-s` is not a popup
any more): a left-click outside does not close it, and cannot be made to. tmux's `popup_key_cb`
returns "keep open" for out-of-bounds mouse events in every version from 3.4 to master _and_
swallows the click, so the program inside never receives it and `--no-mouse` changes nothing. Use
`q` / `Esc`, or the gesture tmux does offer: **right-press outside, drag onto `Close`, release**
(tmux's own popup menu, ≥ 3.3). A right click-and-release in place only opens and closes that menu
again — it is a drag, not a click.

---

## The status bar

**Catppuccin**, on a white terminal. The bar paints no background of its own (`bg=terminal`), so it
takes Ghostty's, and the accent — Latte `blue #1e66f5` — lives only in the pills.

Every tab is **two chips**: the accent holds the index, the name sits on a neutral chip, and each
cap takes the colour of the chip it terminates. That edge inside one object is what stops the
accent reading as a slab — it is the shape Catppuccin itself uses. Inactive tabs get a quiet card
instead of floating on the bar.

- **left** — the current mode (prefix held / copy-mode / zoom / synchronized), rounded like every
  other pill on this bar. Holding the prefix makes the combined pill red; every other displayed
  mode remains blue. It collapses to nothing when idle, so the left is empty outside of one of those
  four states. There used to be a second pill here too, a dedicated `ssh_<host>` marker — it is gone;
  a remote session is still unmistakable from the **right**, whose pill wears the host's own tint
  and shows the session's real name, `ssh_<host>` prefix and all.
- **centre** — the window list, anchored with `status-justify absolute-centre` so the tabs do not
  slide when the session name changes length. Each window carries an icon for what is running in it
  and at most one alert marker: red `!` bell, yellow `◆` silence, or green `●` activity, in
  **bell > silence > activity** priority.
- **right** — the session you are on, as a single **rounded** two-chip pill: a tmux glyph in the
  accent, the name in a neutral chip. It used to hold the session's number instead of the icon, back
  when the whole strip was visible and a digit meant something to compare; with only one pill left
  there was nothing to compare it against, so the space went to the icon. Clicking the pill opens
  the session tree. The strip used to list every session, which is what made the bar collide with
  itself.

### Flavours, and following the system theme

All four flavours ship. `scripts/theme.sh` owns the palette, the semantic roles and the per-host
tints; **switching is one option and a re-run**, from the `Alt-Space` palette or by hand:

```tmux
:set -g @thm_flavor mocha ; run-shell "~/.config/tmux/scripts/theme.sh"
```

Every re-run refreshes existing session pills and the current session strip, plus the colour-typed
clock and pane-selector options. Format-based surfaces follow the same roles, including the tree
preview accent on tmux ≥ 3.7.

On **tmux ≥ 3.6** it does that by itself. tmux 3.6 added mode 2031, so it asks the terminal which
theme it is on and re-asks when the OS flips; the `client-light-theme` / `client-dark-theme` hooks
switch the flavour to match. This is what `tmux-dark-notify` exists to do, minus the plugin and the
daemon. On older tmux the block is skipped and you switch by hand.

### Contrast

The pill text and the inks on coloured search backgrounds are _measured_, not written down. The
right foreground flips both with the flavour and within it — white reads on Latte's blue (4.91:1)
and not on Mocha's (2.10:1), and inside Latte it reads on blue but not on yellow (2.62:1).
`theme.sh` computes each one, so a palette edit cannot silently produce an illegible surface. All
56 Catppuccin accent pairings across the four flavours measure ≥ 4.5:1.

Three places deliberately depart from upstream `catppuccin/tmux`, all for legibility — which
Catppuccin's own style guide asks for over fidelity. Pill text is `#ffffff`, not `crust`, because
crust on an accent clears 4.5:1 on _no_ Latte accent (upstream's own default mauve pill is 4.09:1).
Inactive pane borders use `overlay2`, not `overlay0` (2.60:1 on white, well under the 3:1 UI
threshold) or `overlay1` (3.20:1 — technically past it, but with barely any headroom, and the
`heavy` box-drawing weight it sits on made the shortfall obvious). `overlay2` measures 3.95:1 on
Latte and clears every other flavour by a wider margin still, while staying one of Catppuccin's own
quiet greys rather than reaching for a louder colour. And `message-style` is white on the accent
rather than upstream's teal on
`overlay0`, which is 1.44:1.

### Why nothing on the bar shells out

There is no `#()` anywhere, and the reason is not the one you would guess. tmux caches a `#()` and
re-runs it on the **`status-interval` timer**, not on every redraw. Measured with 6 windows at
`status-interval 5`: 6 forks every 5s, while ordinary redraws reuse the cache. But this config sets
**`status-interval 0`**, so a `#()` would run **once** and then show that value for the life of the
client. The problem with a `#()` here is staleness, not cost — which is exactly why every status
module forces the timer on, and why none of them fit a bar whose `status-right` is the session strip.

---

## Copy mode

`prefix + [`, `Alt-i`, or scroll up. `v` selects; `y` / `Enter` / `Ctrl-C` / mouse-drag-release copy
**without** leaving copy mode, and the selection also reaches the system clipboard. `q` / `Esc` exits.

Searches paint ordinary matches yellow and the current match mauve; the copy-mode mark is red. On
**tmux ≥ 3.6**, a compact position card shows the scroll/search context and a modal blue scrollbar
appears on the right **only in copy/view mode**. That scrollbar temporarily consumes one column, so
the pane narrows and reflows while the mode is active, then returns to its normal width on exit.
tmux 3.4 and 3.5 keep the default position UI and have no scrollbar.

`d` / `u` jump ten lines, like vim's `10j` / `10k` — deliberately not half a page, which `C-d` /
`C-u` already do. They exist because overshooting the bottom with `C-d` sends the extra keypress
through as EOF and closes the shell, while `d` / `u` never leave copy mode.

The `dev` tool windows (`agent · editor · git`) stay put when their app exits — the pane goes _dead_
instead of the window closing, so `prefix + R` relaunches it (`term` stays a disposable shell).

---

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

---

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
- Never set `default-command` with `set -g` — it would make every local session try to SSH. This is
  also why `tmux-sensible` is not installed: on macOS it does exactly that.

---

## Work / per-machine config

At the end of `tmux.conf`, after the plugins, so these override everything:

```tmux
source-file -q ~/.config/tmux-work/work.conf   # private (company) repo, cloned separately
source-file -q ~/.config/tmux/local.conf       # per-machine, gitignored
```

`-q` is silent when the file is absent. The work layer may override global options, styles, and add
its own bindings; use `%if`/`%elif`/`%endif` for host/OS conditionals (parse-time, no subshell).

---

## Why the move from Zellij

Two requirements were structurally impossible in Zellij and are native in tmux:

- **Never mix local and SSH.** In a Zellij `ssh_*` session a new _tab_ entered the remote host but a
  pane _split_ opened a **local** shell, because the `zellij-switch` plugin cannot set `default_shell`
  per session. In tmux, `default-command` is a **session option**: it applies to `new-window` **and**
  `split-window`, and it does not leak to other sessions.
- **Extend the personal config with a work config.** Zellij has no `include`. tmux composes configs
  with `source-file -q`.

### What is lost vs. Zellij

Declarative nested layouts; session persistence across a **reboot** (sessions still survive closing
the terminal and SSH drops); rounded pane-frame corners; and — inside nvim — Kitty-graphics previews.
Accepted trade-offs.

---

## Neovim interplay

- `Alt-hjkl` are `is_vim`-guarded so [smart-splits](https://github.com/mrjones2014/smart-splits.nvim)
  keeps navigating nvim splits and hands off to neighbouring tmux panes at the edge. Set
  `multiplexer_integration = "tmux"` in nvim.
- `set-clipboard on` lets nvim's OSC 52 (yanking over SSH) reach the local clipboard.
- `focus-events on` makes nvim's `FocusGained → checktime` autocmd fire.
- Known regressions under tmux: nvim's OSC 11 light/dark auto-detection may need a pin in
  `~/.nvim-local.lua`; Kitty-graphics image/diagram previews do not survive tmux reliably.

---

## Development

POSIX `sh` with `set -u`, `sh -n` clean; Conventional Commits in English; see `AGENTS.md`. Never
push to `main` without testing the phase on the target machine. Test on an isolated socket
(`tmux -L smoke`), never the running server — and use a **fresh socket name each time**, because
reusing one straight after `kill-server` races and looks like a config error.
