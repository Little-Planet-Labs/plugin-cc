#!/bin/sh
# SessionStart hook for the factory ledger. Runs factory-ledger.mjs with Node.
# It must never break or slow a session: without node on PATH it exits
# silently, and it always exits 0 with nothing on stderr.

command -v node >/dev/null 2>&1 || exit 0

case "$0" in
  */*) hook_dir=${0%/*} ;;
  *) hook_dir=. ;;
esac

node "$hook_dir/factory-ledger.mjs" 2>/dev/null
exit 0
