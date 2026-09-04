#!/bin/sh
# Shared builder for a complete local Git checkout with four exact, network-free submodules.

fixture_fail() {
  printf 'fixture: %s\n' "$*" >&2
  exit 1
}

fixture_repo_root() {
  [ -n "${ROOT:-}" ] || return 1
  printf '%s\n' "$ROOT"
}

fixture_git_commit() {
  fixture_commit_repo=$1
  fixture_commit_message=$2
  git -C "$fixture_commit_repo" add . || return
  git -C "$fixture_commit_repo" \
    -c user.name='Runtime Fixture' -c user.email='runtime-fixture@example.invalid' \
    commit -q -m "$fixture_commit_message"
}

fixture_make_submodule() {
  fixture_source=$1
  fixture_loader=$2
  fixture_loader_name=$3
  mkdir -p "$fixture_source" || return
  git -C "$fixture_source" init -q || return
  cp "$fixture_loader" "$fixture_source/$fixture_loader_name" || return
  chmod +x "$fixture_source/$fixture_loader_name" || return
  fixture_git_commit "$fixture_source" 'fixture loader'
}

fixture_build_repo() {
  fixture_destination=$1
  fixture_root=$(fixture_repo_root) || return
  fixture_sources=${fixture_destination%/*}/submodule-sources

  mkdir -p "$fixture_destination" "$fixture_sources" || return
  cp "$fixture_root/bootstrap.sh" "$fixture_root/tmux.conf" "$fixture_root/README.md" \
    "$fixture_root/AGENTS.md" "$fixture_destination/" || return
  cp -R "$fixture_root/scripts" "$fixture_root/shell" "$fixture_root/sessions" \
    "$fixture_destination/" || return
  cp "$fixture_root/.gitignore" "$fixture_destination/.gitignore" || return
  git -C "$fixture_destination" init -q || return

  fixture_make_submodule "$fixture_sources/extrakto" \
    "$fixture_root/tests/fixtures/plugin-loader.tmux" extrakto.tmux || return
  fixture_make_submodule "$fixture_sources/tmux-easy-motion" \
    "$fixture_root/tests/fixtures/plugin-loader.tmux" easy_motion.tmux || return
  fixture_make_submodule "$fixture_sources/tmux-fuzzback" \
    "$fixture_root/tests/fixtures/plugin-loader.tmux" fuzzback.tmux || return

  fixture_fingers=$fixture_sources/tmux-fingers
  mkdir -p "$fixture_fingers" || return
  git -C "$fixture_fingers" init -q || return
  cp "$fixture_root/tests/fixtures/tmux-fingers.tmux" \
    "$fixture_fingers/tmux-fingers.tmux" || return
  printf 'bin/*\n' > "$fixture_fingers/.gitignore" || return
  chmod +x "$fixture_fingers/tmux-fingers.tmux" || return
  fixture_git_commit "$fixture_fingers" 'fixture Fingers loader' || return

  for fixture_name in extrakto tmux-easy-motion tmux-fingers tmux-fuzzback; do
    git -c protocol.file.allow=always -C "$fixture_destination" submodule add -q \
      "$fixture_sources/$fixture_name" "plugins/$fixture_name" || return
  done
  fixture_git_commit "$fixture_destination" 'complete runtime fixture' || return

  mkdir -p "$fixture_destination/plugins/tmux-fingers/bin" || return
  cp "$fixture_root/tests/fixtures/tmux-fingers" \
    "$fixture_destination/plugins/tmux-fingers/bin/tmux-fingers" || return
  chmod +x "$fixture_destination/plugins/tmux-fingers/bin/tmux-fingers" || return
}

fixture_make_home() {
  fixture_home=$1
  fixture_checkout=$2
  mkdir -p "$fixture_home/.config" || return
  ln -s "$fixture_checkout" "$fixture_home/.config/tmux"
}

fixture_mode() {
  fixture_mode_path=$1
  if stat -f '%Lp' "$fixture_mode_path" >/dev/null 2>&1; then
    stat -f '%Lp' "$fixture_mode_path"
  else
    stat -c '%a' "$fixture_mode_path"
  fi
}
