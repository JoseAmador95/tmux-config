#!/bin/sh
# theme.sh [flavour] — paint the whole config in one Catppuccin flavour.
#
# This is the single source of colour. tmux.conf reads the result with #{E:@thm_…} and the other
# scripts with `tmux display-message -p '#{E:@thm_…}'`. Changing theme is @thm_flavor plus a re-run
# of this script; nothing else in the repo names a colour.
#
#   run-shell "~/.config/tmux/scripts/theme.sh"        # uses @thm_flavor, default latte
#   run-shell "~/.config/tmux/scripts/theme.sh mocha"  # or say it outright
#
# Palettes are catppuccin/palette v1.8.0. They are deliberately NOT copied from catppuccin/tmux's
# own theme files, which ship @thm_subtext_0 and @thm_subtext_1 SWAPPED relative to palette.json —
# the swap is systematic across all four flavours (overlay/surface are fine). The values below use
# palette.json's meaning, so `subtext0` really is the lighter of the two.
#
# WRITE HEX IN LOWERCASE. Inside a #{?…} conditional or an option pulled in with #{E:…}, tmux still
# honours its legacy one-letter shorthands, so "#FFFFFF" loses its "#F" to the window-flags
# shorthand and renders "*FFFFF". "#ffffff" does not — there is no "#f" shorthand.
#
# WHY THE INK IS MEASURED, NOT LISTED. Every pill is text-on-colour, so each needs a foreground
# clearing 4.5:1 on its own background — and the right answer flips with the flavour AND with the
# individual colour. Latte's accents are mid-dark: white works on blue (4.91) and fails on yellow
# (2.62). Frappé/Macchiato/Mocha accents are pastel: white fails on all of them (Mocha blue = 2.10)
# and the flavour's own crust is right (9.2). Four hardcoded ink tables would be ~52 numbers to
# keep honest by hand, so each ink is computed here instead — a palette edit cannot silently
# produce an illegible pill.
set -u

flavour="${1:-}"
[ -n "$flavour" ] || flavour=$(tmux display-message -p '#{@thm_flavor}' 2>/dev/null) || flavour=''
[ -n "$flavour" ] || flavour=latte

# palette.json order — the positional lists below must match it name for name.
NAMES='rosewater flamingo pink mauve red maroon peach yellow green teal sky sapphire blue lavender
       text subtext1 subtext0 overlay2 overlay1 overlay0 surface2 surface1 surface0 base mantle crust'

case "$flavour" in
  latte)
    set -- '#dc8a78' '#dd7878' '#ea76cb' '#8839ef' '#d20f39' '#e64553' '#fe640b' '#df8e1d' '#40a02b' '#179299' '#04a5e5' '#209fb5' '#1e66f5' '#7287fd' '#4c4f69' '#5c5f77' '#6c6f85' '#7c7f93' '#8c8fa1' '#9ca0b0' '#acb0be' '#bcc0cc' '#ccd0da' '#eff1f5' '#e6e9ef' '#dce0e8' ;;
  frappe)
    set -- '#f2d5cf' '#eebebe' '#f4b8e4' '#ca9ee6' '#e78284' '#ea999c' '#ef9f76' '#e5c890' '#a6d189' '#81c8be' '#99d1db' '#85c1dc' '#8caaee' '#babbf1' '#c6d0f5' '#b5bfe2' '#a5adce' '#949cbb' '#838ba7' '#737994' '#626880' '#51576d' '#414559' '#303446' '#292c3c' '#232634' ;;
  macchiato)
    set -- '#f4dbd6' '#f0c6c6' '#f5bde6' '#c6a0f6' '#ed8796' '#ee99a0' '#f5a97f' '#eed49f' '#a6da95' '#8bd5ca' '#91d7e3' '#7dc4e4' '#8aadf4' '#b7bdf8' '#cad3f5' '#b8c0e0' '#a5adcb' '#939ab7' '#8087a2' '#6e738d' '#5b6078' '#494d64' '#363a4f' '#24273a' '#1e2030' '#181926' ;;
  mocha)
    set -- '#f5e0dc' '#f2cdcd' '#f5c2e7' '#cba6f7' '#f38ba8' '#eba0ac' '#fab387' '#f9e2af' '#a6e3a1' '#94e2d5' '#89dceb' '#74c7ec' '#89b4fa' '#b4befe' '#cdd6f4' '#bac2de' '#a6adc8' '#9399b2' '#7f849c' '#6c7086' '#585b70' '#45475a' '#313244' '#1e1e2e' '#181825' '#11111b' ;;
  *)
    tmux display-message "theme: unknown flavour '$flavour' — falling back to latte"
    flavour=latte
    set -- '#dc8a78' '#dd7878' '#ea76cb' '#8839ef' '#d20f39' '#e64553' '#fe640b' '#df8e1d' '#40a02b' '#179299' '#04a5e5' '#209fb5' '#1e66f5' '#7287fd' '#4c4f69' '#5c5f77' '#6c6f85' '#7c7f93' '#8c8fa1' '#9ca0b0' '#acb0be' '#bcc0cc' '#ccd0da' '#eff1f5' '#e6e9ef' '#dce0e8' ;;
esac

# Publish the palette, and keep a shell copy so the ink maths below can read the values back.
for n in $NAMES; do
  eval "C_${n}=\$1"
  tmux set -g "@thm_${n}" "$1"
  shift
done
tmux set -g @thm_flavor "$flavour"

# best_ink <background> — print whichever of the two candidates has more WCAG contrast on it.
# awk because POSIX sh has no floats and the sRGB transfer function needs a real exponent. awk is
# already a dependency (bootstrap.sh, agent.sh) and BSD awk on macOS handles all of this.
best_ink() {
  awk -v bg="$1" -v l="$LIGHT_INK" -v d="$DARK_INK" '
    function hx(s,  i,n)     { n=0; for (i=1;i<=length(s);i++) n=n*16+index("0123456789abcdef",substr(tolower(s),i,1))-1; return n }
    function ch(v)           { v/=255; return (v<=0.03928) ? v/12.92 : ((v+0.055)/1.055)^2.4 }
    function lum(c)          { return 0.2126*ch(hx(substr(c,2,2))) + 0.7152*ch(hx(substr(c,4,2))) + 0.0722*ch(hx(substr(c,6,2))) }
    function cr(a,b,  x,y,t) { x=lum(a); y=lum(b); if (x<y) { t=x; x=y; y=t } return (x+0.05)/(y+0.05) }
    BEGIN { print (cr(bg,l) >= cr(bg,d)) ? l : d }'
}

# The dark candidate is the flavour's own crust when the flavour is dark — in palette, and softer
# than pure black. On a light flavour crust is near-white and useless as ink, so black it is. The
# test is the flavour's own background: if white reads better on it, the flavour is dark.
LIGHT_INK='#ffffff'
DARK_INK='#000000'
[ "$(best_ink "$C_base")" = '#ffffff' ] && DARK_INK="$C_crust"

# --- roles ---------------------------------------------------------------------------------------
# The NAMES survive a flavour change because Catppuccin's greys invert with the flavour by design:
# subtext0 is the quiet foreground and overlay2 the quiet line in every one of them. The named
# colours carry meaning across every visual surface: blue is normal focus, red demands action,
# yellow asks for attention, green reports activity, and mauve singles out the current search hit.
# Every role that can become a background carries its own measured ink; Latte in particular cannot
# share one foreground across this range of luminances.
tmux set -g @thm_accent         "#{@thm_blue}"      # normal focus and active controls
tmux set -g @thm_urgent         "#{@thm_red}"       # prefix held, bells, marked copy line
tmux set -g @thm_attention      "#{@thm_yellow}"    # silence and ordinary search matches
tmux set -g @thm_activity       "#{@thm_green}"     # new activity in another window
tmux set -g @thm_current_search "#{@thm_mauve}"     # the active copy-mode search hit
tmux set -g @thm_dim            "#{@thm_subtext0}"  # inactive tabs, session strip
tmux set -g @thm_line           "#{@thm_overlay2}"  # inactive pane borders
tmux set -g @thm_dead           "#{@thm_maroon}"    # a pane whose process exited
tmux set -g @thm_card           "#{@thm_base}"      # the quiet chip behind an inactive window
tmux set -g @thm_chip           "#{@thm_surface0}"  # the neutral half of an active pill
tmux set -g @thm_sel_bg         "#{@thm_surface0}"  # copy-mode selection
tmux set -g @thm_sel_fg         "#{@thm_text}"

tmux set -g @thm_ink                "$(best_ink "$C_blue")"
tmux set -g @thm_urgent_ink         "$(best_ink "$C_red")"
tmux set -g @thm_attention_ink      "$(best_ink "$C_yellow")"
tmux set -g @thm_activity_ink       "$(best_ink "$C_green")"
tmux set -g @thm_current_search_ink "$(best_ink "$C_mauve")"

# These three options are colour-typed rather than style-typed: tmux rejects a format such as
# #{E:@thm_accent} here. Publish the resolved palette literals on every flavour run instead, so
# clock mode and the pane selector change with the rest of the theme.
tmux set-window-option -g clock-mode-colour "$C_blue"
tmux set-option -g display-panes-active-colour "$C_blue"
tmux set-option -g display-panes-colour "$C_overlay2"

# ssh_<host> pill tints: the 14 colours palette.json flags as accents, minus blue (every LOCAL
# session wears it) and red (the prefix), which leaves exactly 12 — so a remote pill can never be
# mistaken for either. Each carries its own measured ink as "bg:ink", because one foreground cannot
# serve colours this far apart in luminance.
tints=''
for n in rosewater flamingo pink mauve maroon peach yellow green teal sky sapphire lavender; do
  eval "c=\$C_${n}"
  tints="${tints}${tints:+ }${c}:$(best_ink "$c")"
done
tmux set -g @thm_ssh_tints "$tints"

# @pill and @pill_ink are materialised per-session values, not live formats, so a flavour switch
# would otherwise leave every existing session wearing the old palette until it was renamed.
# Keep the actual colour policy in session-color.sh, then rebuild only the current-session strip.
# session-save.sh is deliberately absent: repainting the UI does not change the restart roster.
SCRIPTS=$(cd "$(dirname "$0")" && pwd)
tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r s; do
  [ -n "$s" ] || continue
  "$SCRIPTS/session-color.sh" "$s" | {
    IFS='	' read -r bg ink
    [ -n "$bg" ] && tmux set-option -t "$s" @pill "$bg"
    [ -n "$ink" ] && tmux set-option -t "$s" @pill_ink "$ink"
  }
done
"$SCRIPTS/session-strip.sh"

# --- plugin palettes -------------------------------------------------------------------------------
# tmux-fuzzback takes its fzf colours as one static option string, which would freeze it to whatever
# flavour was current when it was written — dark by default, wrong the moment you are on Latte.
# Publishing it here instead keeps the rule this file exists to enforce: the palette lives in ONE
# place. Re-running theme.sh is already how a flavour switch works, so fuzzback follows for free.
# The roles are the same three fzf-style.sh uses for every other popup, so the popups match.
tmux set -g @fuzzback-fzf-colors \
  "fg+:$(best_ink "$C_blue"),bg+:${C_blue},prompt:${C_blue},pointer:${C_blue},header:${C_subtext0},border:${C_blue},query:${C_blue}"
