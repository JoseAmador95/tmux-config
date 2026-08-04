# Agent Instructions

## Commands

- There is no build step. The config is a set of tmux commands plus POSIX sh scripts.
- Isolated smoke test (never touch the user's real server): `tmux -f tmux.conf -L smoke new-session -d && tmux -L smoke list-keys >/dev/null && tmux -L smoke kill-server`
- Lint every script: `sh -n scripts/*.sh bootstrap.sh` — and `bash -n shell/functions.sh` separately. `functions.sh` is sourced in bash/zsh and its zsh completion block is not valid POSIX sh, so it has never passed `sh -n`; linting it with `sh` reports a syntax error that is not one.
- Reload the live config: `tmux source-file ~/.config/tmux/tmux.conf`
- Install / re-wire (idempotent, downloads nothing): `./bootstrap.sh`
- **Always** test on an isolated socket (`tmux -L smoke` / `-L pruebas`); never against the user's running server.

## High-level architecture

- `tmux.conf` is the real, versioned config, auto-loaded because the repo lives at `~/.config/tmux`. There are no templates — tmux expands `~`/`$HOME` natively.
- `sessions/*.conf` are **sh fragments sourced by the shell functions** (`. dev.conf`) with `$SESS`/`$DIR` in scope — they are **not** loaded with `tmux source-file` (which does not expand shell variables). This keeps any `set-option -t` next to the `new-session`.
- **SSH shield (two layers)**: `scripts/session-created.sh` (the `session-created` hook) sets a per-session `default-command` for every `ssh_*` session, and `scripts/ssh-host.sh` is that command (host by argument; no host → local shell, never SSH). `default-command` is a **session option** → it applies to `new-window` AND `split-window` and never leaks to local sessions.
- `scripts/` are POSIX sh helpers: `theme.sh` (**the palette** — four Catppuccin flavours, the semantic roles, and the measured pill inks), `agent.sh` (resolve the AI agent), `ssh-host.sh`, `split.sh` (split the longer axis), `session-color.sh` (pill colour: the accent for local sessions, a per-host tint for `ssh_*`), `session-goto.sh` (index → `switch-client`), `session-created.sh` (SSH shield + publishes `@pill`; also the `session-renamed` hook), `session-strip.sh` (numbered session list → `@session_strip`), `session-save.sh` (roster of open sessions, replayed by `t`), `session-menu.sh` (the `Alt-s` session manager), `palette.sh` (`Alt-Space` command palette), `keys.sh` (`prefix + ?` cheatsheet), `ask.sh` (Esc-cancellable prompt/confirm), `grab.sh` (tokens off the screen → command line), `fuzzback.sh` (scrollback search → jump), `urls.sh` (URL picker), `promote.sh` (pane → session), `fzf-style.sh` (sourced; the popup palette, read from the theme).
- `shell/functions.sh` defines `t` / `tp` (alias `tcwd`) / `tssh` / `tcopy` / `agent` plus the `ulimit` block; it is sourced from the rc by `bootstrap.sh`.
- **The palette lives in ONE place**: `scripts/theme.sh`. It publishes the 26 Catppuccin colours for the flavour in `@thm_flavor` (latte/frappe/macchiato/mocha, values from `catppuccin/palette` v1.8.0 — NOT from `catppuccin/tmux`, whose theme files ship `subtext_0`/`subtext_1` swapped), then the semantic roles (`@thm_accent`, `@thm_dim`, `@thm_ink`, `@thm_ssh_tints`…). `tmux.conf` reads them with `#{E:@thm_…}`; the scripts read the same options with `tmux display-message -p '#{E:@thm_…}'` and carry a hardcoded fallback only for a run outside tmux. Changing theme is `@thm_flavor` + a re-run — do not reintroduce hex anywhere else. **The pill inks are COMPUTED in awk, not listed**: white reads on Latte's blue and not on Mocha's, and inside Latte it reads on blue and not on yellow, so a hardcoded table would be 56 numbers to keep honest. Style options (`message-style`, `pane-border-style`, …) expand formats on tmux 3.4, verified on an isolated socket, so they can use `#{E:@thm_…}` too.
- The bar is `bg=terminal` — it paints no background, so it takes the terminal's, which is why a light flavour wants a light terminal and a dark one a dark terminal. Ratios quoted in comments are against the bar the flavour assumes (pure white for Latte, the flavour's own base for the dark three); the inks themselves are computed, so they follow whatever the palette says.
- Deviations from upstream `catppuccin/tmux`, all for legibility and all commented in place: on Latte the pill text is `#ffffff`, not `crust` (crust clears 4.5:1 on no Latte accent); inactive borders are `overlay1` not `overlay0` (2.60:1 on white); `message-style` is white-on-accent, not upstream's 1.44:1 teal-on-overlay0.
- Every pill is the accent; only `ssh_<host>` sessions are tinted, from the `@thm_ssh_tints` cycle. Each entry carries its own ink (`bg:ink`) because Latte's accents span luminances — white is legible on mauve and illegible on yellow.
- Nothing on the bar uses `#()`. `@session_strip` is written by a hook and read back with `#{E:@…}`; per-window icons are a nested `#{?#{==:…}}` chain. A `#()` re-runs on the **`status-interval` timer**, not on every redraw (measured: 6 windows at `status-interval 5` = 6 forks per tick; ordinary redraws reuse the cache; `refresh-client -S` bypasses it). Since this config sets `status-interval 0`, a `#()` would run once and then be **stale forever** — that, not fork cost, is why the bar has none, and why no status module (battery/cpu/gitmux) can be added without turning the timer on and taking over `status-right`.
- Work config is layered at the end of `tmux.conf` via `source-file -q` of `~/.config/tmux-work/work.conf` (private repo) and `~/.config/tmux/local.conf` (per-machine, gitignored).
- Neovim interplay: `Alt-hjkl` are `is_vim`-guarded so smart-splits keeps working; nvim's clipboard/focus rely on `set-clipboard on` and `focus-events on`. See README.

## Key conventions

- **English everywhere**: Conventional Commits (subject + body; the body explains the _why_), comments, README, this file.
- POSIX `sh` with `set -u`; keep `sh -n` clean. No bashisms **except** `shell/functions.sh`, which is sourced in zsh/bash and may use `local` and `${var//…}`.
- In `tmux.conf`, `|` is **not** a pipe — every pipe must live inside `run-shell '…'`.
- **Write hex in LOWERCASE.** Inside a `#{?…}` conditional, or inside an option pulled in with `#{E:…}`, tmux still honours the legacy one-letter shorthands, so `#FFFFFF` loses its `#F` to the window-flags shorthand and renders `*FFFFF` — but `#ffffff` does not, because there is no `#f` shorthand. Lowercase (which is how Catppuccin publishes its palette anyway) removes the whole bug class; the `##FFFFFF` escape it used to need is no longer necessary. Commas inside a conditional still need `#,`.
- **Never bundle a tmux flag that takes an argument**: `set-option -tu <name>` parses as `-t u`, silently targeting a session called `u`. Write `-u -t <name>`.
- Anything from a session name is untrusted in a format: escape `#` → `##` before it reaches the status bar.
- The bar and the popups need a **UTF-8 locale**; with `LC_CTYPE=POSIX` tmux silently drops the Nerd Font glyphs (found while testing on an isolated socket).
- Always brace shell vars around multibyte characters (`"${i}·${s}"`) — `/bin/sh` on macOS is bash 3.2 and would read `$i·` as one variable name and trip `set -u`.
- SSH invariants: never `set -g default-command`; sessions are named `ssh_<host>`; document the escape routes by which a pane could still reach a local shell (explicit command, `join-pane`/`move-pane`).
- The `ulimit` block only raises and caps at the hard limit (macOS soft `nofile` is 256, which crashes a multi-pane server).
- Keep the long explanatory comments, including the dead ends — they are why the config looks the way it does.
- Never push to `main` without the user verifying the phase on their Mac; develop on a branch.
