#!/bin/sh
# Minimal offline loader used only by the synthetic submodule fixture.
set -u

fixture_dir=$(cd "$(dirname "$0")" && pwd)
"$fixture_dir/bin/tmux-fingers" version >/dev/null || exit
"$fixture_dir/bin/tmux-fingers" load-config
