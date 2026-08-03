# Agent Instructions

## Commands

- There is no build step. The config is a set of tmux commands plus POSIX sh scripts.
- Isolated smoke test (never touch the user's real server): `tmux -f tmux.conf -L smoke new-session -d && tmux -L smoke list-keys >/dev/null && tmux -L smoke kill-server`
- Lint every script: `sh -n scripts/*.sh bootstrap.sh shell/functions.sh`
- Reload the live config: `tmux source-file ~/.config/tmux/tmux.conf`
- Install / re-wire (idempotent, downloads nothing): `./bootstrap.sh`
- **Always** test on an isolated socket (`tmux -L smoke` / `-L pruebas`); never against the user's running server.

## High-level architecture

- `tmux.conf` is the real, versioned config, auto-loaded because the repo lives at `~/.config/tmux`. There are no templates — tmux expands `~`/`$HOME` natively.
- `sessions/*.conf` are **sh fragments sourced by the shell functions** (`. dev.conf`) with `$SESS`/`$DIR` in scope — they are **not** loaded with `tmux source-file` (which does not expand shell variables). This keeps any `set-option -t` next to the `new-session`.
- **SSH shield (two layers)**: `scripts/session-created.sh` (the `session-created` hook) sets a per-session `default-command` for every `ssh_*` session, and `scripts/ssh-host.sh` is that command (host by argument; no host → local shell, never SSH). `default-command` is a **session option** → it applies to `new-window` AND `split-window` and never leaks to local sessions.
- `scripts/` are POSIX sh helpers: `agent.sh` (resolve the AI agent), `ssh-host.sh`, `split.sh` (split the longer axis), `session-color.sh` (pill colour: the accent for local sessions, a deterministic per-host tint by name CRC for `ssh_*`), `session-goto.sh` (index → `switch-client`), `session-created.sh` (SSH shield + publishes `@pill`; also the `session-renamed` hook and a `--all` sweep), `session-strip.sh` (numbered session list → `@session_strip`), `session-menu.sh` (the `Alt-s` session manager), `palette.sh` (`Alt-Space` command palette), `keys.sh` (`prefix + ?` cheatsheet), `ask.sh` (Esc-cancellable prompt/confirm), `fzf-style.sh` (sourced; the single definition of the popup palette).
- `shell/functions.sh` defines `t` / `tp` (alias `tcwd`) / `tssh` / `tcopy` / `agent` plus the `ulimit` block; it is sourced from the rc by `bootstrap.sh`.
- The status bar uses the `vscode-modern` palette: the bar itself is `bg=terminal` (no background of its own, so it follows the terminal light↔dark) and the accent `#005FB8` lives only in the pills. Every pill is the accent; only `ssh_<host>` sessions are tinted by `session-color.sh` (stable per host), published as the session-scoped `@pill` user option. That palette has two measured constraints: >= 5:1 against the white pill text, and >= 20° of hue from the accent, or a remote session would read as a local one. `scripts/fzf-style.sh` carries the same palette for the popups — change both together.
- Nothing on the bar uses `#()`. `@session_strip` is written by a hook and read back with `#{E:@…}`; per-window icons are a nested `#{?#{==:…}}` chain. A `#()` in `window-status-format` would fork once per window per redraw.
- Work config is layered at the end of `tmux.conf` via `source-file -q` of `~/.config/tmux-work/work.conf` (private repo) and `~/.config/tmux/local.conf` (per-machine, gitignored).
- Neovim interplay: `Alt-hjkl` are `is_vim`-guarded so smart-splits keeps working; nvim's clipboard/focus rely on `set-clipboard on` and `focus-events on`. See README.

## Key conventions

- **English everywhere**: Conventional Commits (subject + body; the body explains the _why_), comments, README, this file.
- POSIX `sh` with `set -u`; keep `sh -n` clean. No bashisms **except** `shell/functions.sh`, which is sourced in zsh/bash and may use `local` and `${var//…}`.
- In `tmux.conf`, `|` is **not** a pipe — every pipe must live inside `run-shell '…'`.
- **Hex inside a `#{?…}` conditional, or inside a user option pulled in with `#{E:…}`, must be escaped**: tmux still honours the legacy one-letter shorthands there, so a literal `#FFFFFF` loses its `#F` to the window-flags shorthand and renders `*FFFFF`. Write `##FFFFFF`. Hex sitting directly in a `#[…]` style is safe unescaped. Commas inside a conditional need `#,`.
- **Never bundle a tmux flag that takes an argument**: `set-option -tu <name>` parses as `-t u`, silently targeting a session called `u`. Write `-u -t <name>`.
- Anything from a session name is untrusted in a format: escape `#` → `##` before it reaches the status bar.
- The bar and the popups need a **UTF-8 locale**; with `LC_CTYPE=POSIX` tmux silently drops the Nerd Font glyphs (found while testing on an isolated socket).
- Always brace shell vars around multibyte characters (`"${i}·${s}"`) — `/bin/sh` on macOS is bash 3.2 and would read `$i·` as one variable name and trip `set -u`.
- SSH invariants: never `set -g default-command`; sessions are named `ssh_<host>`; document the escape routes by which a pane could still reach a local shell (explicit command, `join-pane`/`move-pane`).
- The `ulimit` block only raises and caps at the hard limit (macOS soft `nofile` is 256, which crashes a multi-pane server).
- Keep the long explanatory comments, including the dead ends — they are why the config looks the way it does.
- Never push to `main` without the user verifying the phase on their Mac; develop on a branch.
