#!/bin/sh
# The optional source makes the fixture detect accidental exposure of untracked submodule content.
fixture_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P) || exit
if [ -f "$fixture_dir/untracked-runtime.sh" ]; then
  # shellcheck source=/dev/null
  . "$fixture_dir/untracked-runtime.sh"
fi
exit 0
