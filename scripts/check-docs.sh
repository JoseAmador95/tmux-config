#!/bin/sh
# check-docs.sh — assert every key binding this config defines is documented in BOTH README.md and
# scripts/keys.sh.
#
# ONE DIRECTION ONLY: it catches a key that exists but is undocumented, not a doc entry for a key
# that no longer exists. The reverse needs parsing prose back into key names, and a wrong guess
# there would fail the build over a sentence. Deleting a binding still means editing both docs by
# hand. Run it with plugins/ present, or the plugin-owned keys are simply absent and pass silently.
#
# This is a lint, not a runtime helper: nothing in tmux.conf calls it. Run it after touching keys.
#   ./scripts/check-docs.sh            # exit 0 = in sync
#
# WHY IT EXISTS: keys.sh is the `prefix + ?` popup and README has the long table. Two hand-kept
# copies of the same list drift the first time a plugin moves a key, and the drift is invisible —
# the popup still opens, it just lies. Plugins made this a live risk: five of them bind keys now.
#
# HOW IT DECIDES what is "ours": it diffs against a tmux started with `-f /dev/null`, so tmux's own
# defaults are excluded and only what this config adds or overrides is checked.
#
# The docs spell keys for humans — `Alt-h/j/k/l`, `Alt-←`, `prefix + H/J/K/L` — while tmux says
# M-h, M-Left, H. Both sides are normalised before comparing, and grouped spellings are expanded,
# or this would report a wall of false failures (it did, which is why the normalising is here).
set -u

cd "$(dirname "$0")/.." || exit 1
[ -f tmux.conf ] || { echo "check-docs: run from the repo"; exit 1; }

SOCK="docchk$$"
VAN="docvan$$"
TMP="${TMPDIR:-/tmp}/check-docs.$$"
mkdir -p "$TMP" || exit 1
cleanup() { tmux -L "$SOCK" kill-server 2>/dev/null; tmux -L "$VAN" kill-server 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

tmux -f /dev/null -L "$VAN"  new-session -d 2>/dev/null || { echo "check-docs: cannot start tmux"; exit 1; }
tmux -f tmux.conf -L "$SOCK" new-session -d 2>/dev/null || { echo "check-docs: tmux.conf failed to load"; exit 1; }

keys() {   # keys() <socket> <table> -> one key per line
  # list-keys QUOTES a key that needs it, so `bind -n "M-;"` comes back as the five characters
  # "M-;" — quotes included. Strip them, or every quoted key reports as undocumented no matter what
  # the docs say. (Found by this script the first time a quoted key was added.)
  tmux -L "$1" list-keys -T "$2" 2>/dev/null |
    awk -v t="$2" '{for (i=1;i<=NF;i++) if ($i==t) { k=$(i+1); gsub(/^"|"$/,"",k); print k; break }}' |
    sort -u
}

# Expand the grouped spellings the docs use into one token per line, so `Alt-h/j/k/l` matches a
# lookup for `Alt-j`. Everything is lowercased; matching is substring, which is why the tokens are
# kept long enough to be unambiguous.
flatten() {
  sed -e 's#\(Alt-\|M-\)\([A-Za-z0-9]\)/\([A-Za-z0-9]\)/\([A-Za-z0-9]\)/\([A-Za-z0-9]\)#\1\2 \1\3 \1\4 \1\5#g' \
      -e 's#\(prefix + \)\([A-Za-z]\)/\([A-Za-z]\)/\([A-Za-z]\)/\([A-Za-z]\)#\1\2 \1\3 \1\4 \1\5#g' \
      -e 's#\([A-Za-z-]*\) / \([A-Za-z-]*\)#\1 \2#g' \
      -e 's#`\([^`]*\)`#\1#g' "$1" | tr 'A-Z' 'a-z'
}
flatten README.md      > "$TMP/readme"
flatten scripts/keys.sh > "$TMP/keys"

# tmux spelling -> every spelling a doc is allowed to use. ALL are printed and any one counts:
# README.md writes Alt-h for readability, keys.sh writes M-h to match what tmux prints, and both
# are correct. Accepting only one of them is what made the first run of this script cry wolf.
doc_spelling() {
  low=$(printf '%s' "$1" | tr 'A-Z' 'a-z')
  case "$1" in
    M-Left)            printf 'alt-left\nalt-←\nm-left\n' ;;
    M-Right)           printf 'alt-right\nalt-→\nm-right\n' ;;
    M-*)               printf 'alt-%s\nm-%s\n' "${low#m-}" "${low#m-}" ;;
    MouseDown1Status*) printf 'session strip\nsession pill\n' ;;
    MouseDragEnd1Pane) printf 'mouse-drag-release\nmouse-drag\n' ;;
    *)                 printf '%s\n' "$low" ;;
  esac
}

# Keys deliberately not in the user-facing lists, with the reason. Anything not here must be
# documented; anything here must stay justified.
exempt() {
  case "$1" in
    C-a|C-Space) return 0 ;;   # send-prefix passthrough: plumbing for the leader, not a command
    [1-9]|M-[1-9]) return 0 ;; # digit runs; documented as the ranges prefix + 1...9 / Alt-1...9
    *) return 1 ;;
  esac
}

fail=0
for tbl in prefix root copy-mode-vi; do
  keys "$VAN" "$tbl" > "$TMP/van"
  keys "$SOCK" "$tbl" | comm -13 "$TMP/van" - > "$TMP/ours"
  while IFS= read -r k; do
    [ -n "$k" ] || continue
    exempt "$k" && continue
    doc_spelling "$k" > "$TMP/spellings"
    for doc in readme keys; do
      hit=0
      while IFS= read -r s; do
        [ -n "$s" ] || continue
        if grep -qF -- "$s" "$TMP/$doc"; then hit=1; break; fi
      done < "$TMP/spellings"
      if [ "$hit" -eq 0 ]; then
        case "$doc" in
          readme) echo "  undocumented in README.md    : [$tbl] $k" ;;
          keys)   echo "  undocumented in keys.sh      : [$tbl] $k" ;;
        esac
        fail=1
      fi
    done
  done < "$TMP/ours"
done

if [ "$fail" -eq 0 ]; then
  echo "check-docs: every custom binding appears in README.md and scripts/keys.sh"
fi
exit "$fail"
