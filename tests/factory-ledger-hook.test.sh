#!/bin/sh
# Tests for the little-planet-factory SessionStart ledger hook.
#
# Feeds hook input JSON on stdin to the command registered in
# plugins/little-planet-factory/hooks/hooks.json, run the way Claude Code runs
# it (through a shell, with CLAUDE_PLUGIN_ROOT set), and checks what it prints.
#
# Usage: sh tests/factory-ledger-hook.test.sh
# Needs node on PATH (the hook needs it too). Prints PASS/FAIL per test and
# exits non-zero if any test fails.

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLUGIN_ROOT="$REPO_ROOT/plugins/little-planet-factory"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
OVERSEER=little-planet-factory:overseer
FOLLOW_LINE="Follow the overseer's \"After compaction\" steps before doing anything else."

if ! command -v node >/dev/null 2>&1; then
  echo "FAIL: node is required to run these tests" >&2
  exit 1
fi

# The test process may itself run inside a plugin hook environment, or a lite
# session.
unset CLAUDE_PLUGIN_DATA LPF_TIER

tmp_root=${TMPDIR:-/tmp}
WORK=$(mktemp -d "${tmp_root%/}/factory-ledger-test.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' INT TERM
mkdir -p "$WORK/outputs"
OUT="$WORK/stdout"
ERR="$WORK/stderr"
CTX="$WORK/context"
CTXLEN="$WORK/context-length"
OUTPUT_COUNT=0

HOOK_CMD=$(node -e '
const config = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
process.stdout.write(config.hooks.SessionStart[0].hooks[0].command);
' "$HOOKS_JSON") || { echo "FAIL: can't read the hook command from $HOOKS_JSON" >&2; exit 1; }

# run_hook <stdin-file> [VAR=value ...]
# Runs the registered command with the given environment. Sets RC, and keeps
# every non-empty stdout for output_is_valid_json.
run_hook() {
  hook_input=$1
  shift
  env "$@" CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" /bin/sh -c "$HOOK_CMD" <"$hook_input" >"$OUT" 2>"$ERR"
  RC=$?
  if [ -s "$OUT" ]; then
    OUTPUT_COUNT=$((OUTPUT_COUNT + 1))
    cp "$OUT" "$WORK/outputs/$OUTPUT_COUNT.json"
  fi
}

# write_input <file> <source> <agent_type or ""> <scratchpad_dir or "-" to omit> [session_id]
write_input() {
  file=$1 source=$2 agent=$3 scratch=$4 session=${5:-abc123}
  {
    printf '{"session_id":"%s","transcript_path":"/nonexistent/t.jsonl","cwd":"%s",' "$session" "$WORK"
    printf '"permission_mode":"default","hook_event_name":"SessionStart","source":"%s"' "$source"
    [ "$scratch" != "-" ] && printf ',"scratchpad_dir":"%s"' "$scratch"
    [ -n "$agent" ] && printf ',"agent_id":"agent-1","agent_type":"%s"' "$agent"
    printf '}'
  } >"$file"
}

# Parses $OUT, checks its shape, and writes additionalContext to $CTX and its
# length in UTF-16 code units (JavaScript string length) to $CTXLEN.
extract_context() {
  node -e '
const fs = require("fs");
const out = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const keys = Object.keys(out);
if (keys.length !== 1 || keys[0] !== "hookSpecificOutput") throw new Error("unexpected top-level keys " + keys);
const specific = out.hookSpecificOutput;
if (specific.hookEventName !== "SessionStart") throw new Error("hookEventName is " + specific.hookEventName);
if (typeof specific.additionalContext !== "string") throw new Error("additionalContext is not a string");
fs.writeFileSync(process.argv[2], specific.additionalContext);
fs.writeFileSync(process.argv[3], String(specific.additionalContext.length));
' "$OUT" "$CTX" "$CTXLEN" 2>"$WORK/extract-error"
}

T_OK=1
fail() {
  T_OK=0
  echo "    $1"
}

expect_silent() {
  [ "$RC" -eq 0 ] || fail "$1: exit code $RC, expected 0"
  [ -s "$OUT" ] && fail "$1: expected no stdout, got: $(head -c 300 "$OUT")"
  [ -s "$ERR" ] && fail "$1: expected no stderr, got: $(head -c 300 "$ERR")"
}

# expect_context <label> <expected-context-file>
expect_context() {
  [ "$RC" -eq 0 ] || fail "$1: exit code $RC, expected 0"
  if [ ! -s "$OUT" ]; then
    fail "$1: expected output, got none"
    return
  fi
  if ! extract_context; then
    fail "$1: output isn't valid hook JSON: $(cat "$WORK/extract-error")"
    return
  fi
  if ! cmp -s "$CTX" "$2"; then
    fail "$1: additionalContext differs from expected"
    diff "$2" "$CTX" | head -20 | sed 's/^/      /'
  fi
}

# write_block <expected-file> <kind> <ledger-path> <ledger-file>
write_block() {
  {
    printf 'Factory ledger re-injected after %s: %s\n' "$2" "$3"
    printf '%s\n' "$FOLLOW_LINE"
    printf -- '---\n'
    cat "$4"
  } >"$1"
}

write_pointer() { # <file> <ledger-path> <size>
  printf '%s' "Factory ledger at $2 is $3 bytes, too large to re-inject. Read it in full, then follow the overseer's \"After compaction\" steps before doing anything else." >"$1"
}

new_dir() {
  mktemp -d "$WORK/case.XXXXXX"
}

repeat_char() { # <count> <char>
  head -c "$1" /dev/zero | tr '\0' "$2"
}

# Lists a tree (without . and .., so the snapshot files themselves don't show)
# with every file's checksum.
snapshot() {
  ls -lAR "$1"
  find "$1" -type f -exec cksum {} \; | sort
}

PASSED=0
FAILED=0
run_test() {
  T_OK=1
  "$1"
  if [ "$T_OK" -eq 1 ]; then
    echo "PASS $1"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL $1"
    FAILED=$((FAILED + 1))
  fi
}

# ---------------------------------------------------------------------------

hooks_json_registers_session_start_for_all_sources() {
  node -e '
const config = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
const groups = config.hooks.SessionStart;
if (!Array.isArray(groups) || groups.length !== 1) throw new Error("expected one SessionStart group");
if ("matcher" in groups[0]) throw new Error("SessionStart group has a matcher");
const hook = groups[0].hooks[0];
if (hook.type !== "command") throw new Error("hook type is " + hook.type);
if (!(hook.timeout > 0 && hook.timeout <= 10)) throw new Error("timeout is " + hook.timeout);
if (Object.keys(config.hooks).join() !== "SessionStart,PreToolUse") throw new Error("unexpected events " + Object.keys(config.hooks));
' "$HOOKS_JSON" 2>"$WORK/extract-error" || fail "hooks.json: $(cat "$WORK/extract-error")"
}

non_overseer_without_ledger_outputs_nothing() {
  d=$(new_dir)
  write_input "$d/in.json" startup "" "$d"
  run_hook "$d/in.json"
  expect_silent "startup, no agent_type, no ledger"
  write_input "$d/in.json" compact "" "$d"
  run_hook "$d/in.json"
  expect_silent "compact, no agent_type, no ledger"
}

overseer_startup_announces_path() {
  d=$(new_dir)
  mkdir "$d/data"
  write_input "$d/in.json" startup "$OVERSEER" "$d"
  printf 'Factory ledger for this session: %s/factory-ledger.md' "$d" >"$d/expected"
  # CLAUDE_PLUGIN_DATA plays no part in the path.
  run_hook "$d/in.json" CLAUDE_PLUGIN_DATA="$d/data"
  expect_context "overseer startup" "$d/expected"
  [ "$(cat "$CTXLEN")" = "$(wc -c <"$d/expected" | tr -d ' ')" ] || fail "context length mismatch"
  write_input "$d/in.json" startup "some-plugin:other-agent" "$d"
  run_hook "$d/in.json"
  expect_silent "other agent_type is not announced"
}

# Content with characters JSON must escape, multi-byte UTF-8 (including a
# 4-byte character), a control character, and a trailing newline.
write_tricky_ledger() {
  printf '# Factory ledger\n"quoted" back\\slash\ttab \001ctrl\r\nna\303\257ve \360\237\214\215 planet </script>\n\n- agent a1: running\n' >"$1"
}

compact_injects_existing_ledger_without_agent_type() {
  d=$(new_dir)
  write_tricky_ledger "$d/factory-ledger.md"
  write_input "$d/in.json" compact "" "$d"
  write_block "$d/expected" compaction "$d/factory-ledger.md" "$d/factory-ledger.md"
  run_hook "$d/in.json"
  expect_context "compact, no agent_type" "$d/expected"
}

resume_injects_existing_ledger() {
  d=$(new_dir)
  write_tricky_ledger "$d/factory-ledger.md"
  write_input "$d/in.json" resume "" "$d"
  write_block "$d/expected" resume "$d/factory-ledger.md" "$d/factory-ledger.md"
  run_hook "$d/in.json"
  expect_context "resume" "$d/expected"
  head -n 1 "$CTX" | grep -q '^Factory ledger re-injected after resume: ' || fail "header doesn't say after resume"
}

overseer_compact_announces_then_injects() {
  d=$(new_dir)
  write_tricky_ledger "$d/factory-ledger.md"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  {
    printf 'Factory ledger for this session: %s/factory-ledger.md\n\n' "$d"
    write_block "$d/block" compaction "$d/factory-ledger.md" "$d/factory-ledger.md"
    cat "$d/block"
  } >"$d/expected"
  run_hook "$d/in.json"
  expect_context "overseer compact" "$d/expected"
}

startup_and_clear_do_not_inject_contents() {
  d=$(new_dir)
  write_tricky_ledger "$d/factory-ledger.md"
  printf 'Factory ledger for this session: %s/factory-ledger.md' "$d" >"$d/expected"
  for source in startup clear fork; do
    write_input "$d/in.json" "$source" "" "$d"
    run_hook "$d/in.json"
    expect_silent "$source, no agent_type"
    write_input "$d/in.json" "$source" "$OVERSEER" "$d"
    run_hook "$d/in.json"
    expect_context "$source, overseer: announcement only" "$d/expected"
  done
}

empty_ledger_is_not_injected() {
  d=$(new_dir)
  : >"$d/factory-ledger.md"
  write_input "$d/in.json" compact "" "$d"
  run_hook "$d/in.json"
  expect_silent "empty ledger, no agent_type"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  printf 'Factory ledger for this session: %s/factory-ledger.md' "$d" >"$d/expected"
  run_hook "$d/in.json"
  expect_context "empty ledger, overseer: announcement only" "$d/expected"
}

ledger_directory_is_not_injected() {
  d=$(new_dir)
  mkdir "$d/factory-ledger.md"
  printf 'inside a directory\n' >"$d/factory-ledger.md/notes.md"
  write_input "$d/in.json" compact "" "$d"
  run_hook "$d/in.json"
  expect_silent "ledger is a directory, no agent_type"
  # A ledger path that isn't a regular file is an error, so nothing is output.
  write_input "$d/in.json" resume "$OVERSEER" "$d"
  run_hook "$d/in.json"
  expect_silent "ledger is a directory, overseer"
}

oversized_ledger_injects_pointer_only() {
  d=$(new_dir)
  ledger="$d/factory-ledger.md"
  write_input "$d/in.json" compact "" "$d"

  # Boundary: a total of exactly 9,000 characters is injected in full.
  printf 'Factory ledger re-injected after compaction: %s\n%s\n---\n' "$ledger" "$FOLLOW_LINE" >"$d/header"
  header_len=$(wc -c <"$d/header" | tr -d ' ')
  repeat_char $((9000 - header_len)) x >"$ledger"
  write_block "$d/expected" compaction "$ledger" "$ledger"
  run_hook "$d/in.json"
  expect_context "total of exactly 9000" "$d/expected"
  [ "$(cat "$CTXLEN" 2>/dev/null)" = 9000 ] || fail "expected context length 9000, got $(cat "$CTXLEN" 2>/dev/null)"

  # One character over: pointer only. The ledger is small enough to read.
  repeat_char $((9001 - header_len)) x >"$ledger"
  write_pointer "$d/expected" "$ledger" $((9001 - header_len))
  run_hook "$d/in.json"
  expect_context "total of 9001" "$d/expected"

  # Far over: taken from the file size without reading it.
  repeat_char 100000 y >"$ledger"
  write_pointer "$d/expected" "$ledger" 100000
  run_hook "$d/in.json"
  expect_context "100000-byte ledger" "$d/expected"
  grep -q yyyy "$CTX" && fail "ledger contents leaked into the pointer"
  [ "$(cat "$CTXLEN")" -lt 10000 ] || fail "context is $(cat "$CTXLEN") characters"

  # Overseer: announcement, blank line, pointer. The announcement pushes a
  # ledger that would fit on its own over the limit.
  repeat_char $((9000 - header_len)) x >"$ledger"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  {
    printf 'Factory ledger for this session: %s\n\n' "$ledger"
    write_pointer "$d/pointer" "$ledger" $((9000 - header_len))
    cat "$d/pointer"
  } >"$d/expected"
  run_hook "$d/in.json"
  expect_context "overseer, oversized" "$d/expected"
  [ "$(cat "$CTXLEN")" -lt 10000 ] || fail "context is $(cat "$CTXLEN") characters"
}

no_scratchpad_outputs_nothing() {
  d=$(new_dir)
  data="$d/plugin-data"
  mkdir -p "$data/ledgers"
  # A ledger at the removed fallback location, <data>/ledgers/<session_id>.md.
  # A hook that still used it would announce or inject it.
  write_tricky_ledger "$data/ledgers/sess42.md"
  for source in startup compact resume; do
    for agent in "" "$OVERSEER"; do
      write_input "$d/in.json" "$source" "$agent" - sess42
      run_hook "$d/in.json" CLAUDE_PLUGIN_DATA="$data"
      expect_silent "$source, agent_type '$agent', no scratchpad_dir"
      write_input "$d/in.json" "$source" "$agent" "" sess42
      run_hook "$d/in.json" CLAUDE_PLUGIN_DATA="$data"
      expect_silent "$source, agent_type '$agent', empty scratchpad_dir"
      for bad in 42 null true '["x"]' '{}'; do
        printf '{"session_id":"sess42","cwd":"%s","hook_event_name":"SessionStart","source":"%s","agent_type":"%s","scratchpad_dir":%s}' \
          "$WORK" "$source" "$agent" "$bad" >"$d/in.json"
        run_hook "$d/in.json" CLAUDE_PLUGIN_DATA="$data"
        expect_silent "$source, agent_type '$agent', scratchpad_dir $bad"
      done
    done
  done
  [ "$(ls -A "$data/ledgers")" = sess42.md ] || fail "plugin data ledgers directory changed: $(ls -A "$data/ledgers")"
}

# write_repeated <file> <count> <string>: the string repeated, as UTF-8.
write_repeated() {
  node -e 'process.stdout.write(process.argv[2].repeat(Number(process.argv[1])))' "$2" "$3" >"$1"
}

multibyte_oversized_ledger_reports_bytes() {
  d=$(new_dir)
  ledger="$d/factory-ledger.md"
  write_input "$d/in.json" compact "" "$d"

  # 9,500 characters, 19,000 bytes: read, too long once composed.
  write_repeated "$ledger" 9500 "$(printf '\303\251')"
  [ "$(wc -c <"$ledger" | tr -d ' ')" = 19000 ] || fail "test setup: ledger isn't 19000 bytes"
  write_pointer "$d/expected" "$ledger" 19000
  run_hook "$d/in.json"
  expect_context "9500 two-byte characters" "$d/expected"
  [ "$(cat "$CTXLEN")" -lt 10000 ] || fail "context is $(cat "$CTXLEN") characters"

  # 20,000 characters, 40,000 bytes: over the read cap, sized from stat.
  write_repeated "$ledger" 20000 "$(printf '\303\251')"
  write_pointer "$d/expected" "$ledger" 40000
  run_hook "$d/in.json"
  expect_context "20000 two-byte characters" "$d/expected"

  # Overseer: announcement, blank line, pointer with the byte count.
  write_repeated "$ledger" 9500 "$(printf '\303\251')"
  write_input "$d/in.json" resume "$OVERSEER" "$d"
  {
    printf 'Factory ledger for this session: %s\n\n' "$ledger"
    write_pointer "$d/pointer" "$ledger" 19000
    cat "$d/pointer"
  } >"$d/expected"
  run_hook "$d/in.json"
  expect_context "overseer, 9500 two-byte characters" "$d/expected"
  [ "$(cat "$CTXLEN")" -lt 10000 ] || fail "context is $(cat "$CTXLEN") characters"

  # The limit is in characters, not bytes: 3,000 four-byte characters are
  # 12,000 bytes but 6,000 UTF-16 code units, so they're injected in full.
  write_repeated "$ledger" 3000 "$(printf '\360\237\214\215')"
  write_input "$d/in.json" compact "" "$d"
  write_block "$d/expected" compaction "$ledger" "$ledger"
  run_hook "$d/in.json"
  expect_context "3000 four-byte characters" "$d/expected"
}

fifo_ledger_does_not_hang() {
  d=$(new_dir)
  fifo="$d/factory-ledger.md"
  mkfifo "$fifo"
  # A FIFO isn't a regular file, which is an error, so nothing is output.
  for source in compact resume; do
    for agent in "" "$OVERSEER"; do
      write_input "$d/in.json" "$source" "$agent" "$d"
      rm -f "$d/rc"
      (
        env CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" /bin/sh -c "$HOOK_CMD" <"$d/in.json" >"$OUT" 2>"$ERR"
        echo $? >"$d/rc"
      ) &
      runner=$!
      # Wait up to 2 seconds, well under the hook's 5-second self-timeout. A
      # blocking open of the FIFO would also block that timeout, so on a hang
      # open the FIFO for writing (non-blocking) to release the hook, then fail.
      tries=0
      while [ ! -f "$d/rc" ] && [ "$tries" -lt 20 ]; do
        sleep 0.1
        tries=$((tries + 1))
      done
      if [ ! -f "$d/rc" ]; then
        fail "FIFO ledger, $source, agent_type '$agent': still running after 2 seconds"
        node -e '
const fs = require("fs");
try { fs.closeSync(fs.openSync(process.argv[1], fs.constants.O_WRONLY | fs.constants.O_NONBLOCK)); } catch {}
' "$fifo"
      fi
      wait "$runner"
      RC=$(cat "$d/rc")
      expect_silent "FIFO ledger, $source, agent_type '$agent'"
    done
  done
}

# A symlinked ledger is followed when it resolves inside the scratchpad, and
# is an error (no output) when it resolves anywhere else.
symlinked_ledger_behavior() {
  d=$(new_dir)
  ledger="$d/factory-ledger.md"
  mkdir "$d/notes"
  write_tricky_ledger "$d/notes/state.md"

  ln -s notes/state.md "$ledger"
  write_input "$d/in.json" compact "" "$d"
  write_block "$d/expected" compaction "$ledger" "$d/notes/state.md"
  run_hook "$d/in.json"
  expect_context "symlink to a file inside the scratchpad" "$d/expected"

  # The scratchpad itself reached through a symlinked directory.
  link="$WORK/scratch-link"
  ln -s "$d" "$link"
  write_input "$d/in.json" compact "" "$link"
  write_block "$d/expected" compaction "$link/factory-ledger.md" "$d/notes/state.md"
  run_hook "$d/in.json"
  expect_context "scratchpad through a symlinked directory" "$d/expected"
  rm "$link"

  outside=$(new_dir)
  printf 'outside the scratchpad\n' >"$outside/secret.md"
  rm "$ledger"
  ln -s "$outside/secret.md" "$ledger"
  for agent in "" "$OVERSEER"; do
    write_input "$d/in.json" compact "$agent" "$d"
    run_hook "$d/in.json"
    expect_silent "absolute symlink outside the scratchpad, agent_type '$agent'"
  done
  rm "$ledger"
  ln -s "../$(basename "$outside")/secret.md" "$ledger"
  write_input "$d/in.json" resume "$OVERSEER" "$d"
  run_hook "$d/in.json"
  expect_silent "relative symlink escaping the scratchpad"

  # A dangling symlink counts as no ledger.
  rm "$ledger"
  ln -s notes/missing.md "$ledger"
  write_input "$d/in.json" compact "" "$d"
  run_hook "$d/in.json"
  expect_silent "dangling symlink, no agent_type"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  printf 'Factory ledger for this session: %s' "$ledger" >"$d/expected"
  run_hook "$d/in.json"
  expect_context "dangling symlink, overseer: announcement only" "$d/expected"
}

garbage_stdin_is_silent() {
  d=$(new_dir)
  for garbage in 'not json {' '[1,2,3]' 'null' '"a string"' '42' '{"source":' "$(printf '\377\376\000')"; do
    printf '%s' "$garbage" >"$d/in.json"
    run_hook "$d/in.json" CLAUDE_PLUGIN_DATA="$d"
    expect_silent "stdin '$garbage'"
  done
  # Wrong field types.
  printf '{"source":"compact","agent_type":"%s","scratchpad_dir":42,"session_id":7}' "$OVERSEER" >"$d/in.json"
  run_hook "$d/in.json" CLAUDE_PLUGIN_DATA="$d"
  expect_silent "non-string fields"
}

empty_stdin_is_silent() {
  d=$(new_dir)
  : >"$d/in.json"
  run_hook "$d/in.json" CLAUDE_PLUGIN_DATA="$d"
  expect_silent "empty stdin"
  run_hook /dev/null
  expect_silent "stdin from /dev/null"
}

invalid_utf8_ledger_is_silent() {
  d=$(new_dir)
  printf 'ok so far \377\376 then bad bytes\n' >"$d/factory-ledger.md"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  run_hook "$d/in.json"
  expect_silent "non-UTF-8 ledger"
}

unreadable_ledger_is_silent() {
  d=$(new_dir)
  printf 'private\n' >"$d/factory-ledger.md"
  chmod 000 "$d/factory-ledger.md"
  if cat "$d/factory-ledger.md" >/dev/null 2>&1; then
    chmod 600 "$d/factory-ledger.md"
    echo "    SKIP: running as a user who can read mode-000 files"
    return
  fi
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  run_hook "$d/in.json"
  chmod 600 "$d/factory-ledger.md"
  expect_silent "unreadable ledger"
}

missing_node_is_silent() {
  d=$(new_dir)
  mkdir "$d/bin"
  ln -s "$(command -v sh)" "$d/bin/sh"
  if env PATH="$d/bin" /bin/sh -c 'command -v node' >/dev/null 2>&1; then
    fail "test setup: node is still reachable"
    return
  fi
  # With node this input would produce output, so silence means the wrapper
  # stopped because node is missing.
  write_tricky_ledger "$d/factory-ledger.md"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  run_hook "$d/in.json" PATH="$d/bin"
  expect_silent "no node on PATH"
}

hook_writes_nothing() {
  d=$(new_dir)
  mkdir -p "$d/scratch" "$d/data"
  write_tricky_ledger "$d/scratch/factory-ledger.md"
  snapshot "$PLUGIN_ROOT/hooks" >"$WORK/before-plugin"
  for source in compact resume startup; do
    write_input "$d/in-$source.json" "$source" "$OVERSEER" "$d/scratch"
    write_input "$d/no-scratch-$source.json" "$source" "$OVERSEER" - sess42
  done
  snapshot "$d" >"$WORK/before-work"
  for source in compact resume startup; do
    run_hook "$d/in-$source.json" CLAUDE_PLUGIN_DATA="$d/data"
    run_hook "$d/no-scratch-$source.json" CLAUDE_PLUGIN_DATA="$d/data"
  done
  snapshot "$d" >"$WORK/after-work"
  snapshot "$PLUGIN_ROOT/hooks" >"$WORK/after-plugin"
  cmp -s "$WORK/before-work" "$WORK/after-work" || {
    fail "scratch tree changed"
    diff "$WORK/before-work" "$WORK/after-work" | head -20 | sed 's/^/      /'
  }
  cmp -s "$WORK/before-plugin" "$WORK/after-plugin" || fail "plugin hooks directory changed"
  [ -z "$(ls -A "$d/data")" ] || fail "created something under CLAUDE_PLUGIN_DATA: $(ls -A "$d/data")"
}

# The tier line follows the ledger line, for the overseer only, on every
# source, and only when LPF_TIER is exactly "lite".
overseer_lite_announces_tier() {
  d=$(new_dir)
  printf 'Factory ledger for this session: %s/factory-ledger.md\nFactory tier: lite' "$d" >"$d/expected"
  for source in startup resume compact clear fork; do
    write_input "$d/in.json" "$source" "$OVERSEER" "$d"
    run_hook "$d/in.json" LPF_TIER=lite
    expect_context "$source, overseer, lite, no ledger" "$d/expected"
  done
  [ "$(head -n 1 "$CTX")" = "Factory ledger for this session: $d/factory-ledger.md" ] || fail "first line isn't the ledger line"
  [ "$(sed -n 2p "$CTX")" = "Factory tier: lite" ] || fail "second line isn't the tier line"

  printf 'Factory ledger for this session: %s/factory-ledger.md' "$d" >"$d/expected"
  for tier in "" full LITE " lite" "lite "; do
    write_input "$d/in.json" startup "$OVERSEER" "$d"
    run_hook "$d/in.json" LPF_TIER="$tier"
    expect_context "startup, overseer, LPF_TIER '$tier'" "$d/expected"
  done
  run_hook "$d/in.json"
  expect_context "startup, overseer, LPF_TIER unset" "$d/expected"
}

lite_tier_line_is_overseer_only() {
  d=$(new_dir)
  for source in startup compact; do
    for agent in "" "some-plugin:other-agent" "little-planet-factory:manager"; do
      write_input "$d/in.json" "$source" "$agent" "$d"
      run_hook "$d/in.json" LPF_TIER=lite
      expect_silent "$source, agent_type '$agent', lite, no ledger"
    done
  done
  # A non-overseer still gets the re-injected ledger, without the tier line.
  write_tricky_ledger "$d/factory-ledger.md"
  write_input "$d/in.json" compact "" "$d"
  write_block "$d/expected" compaction "$d/factory-ledger.md" "$d/factory-ledger.md"
  run_hook "$d/in.json" LPF_TIER=lite
  expect_context "compact, no agent_type, lite" "$d/expected"
}

# Without a scratchpad there's no ledger line, but the lite overseer still gets
# the tier line alone, on every source. Nobody else gets anything.
lite_overseer_without_scratchpad_gets_tier_only() {
  d=$(new_dir)
  printf 'Factory tier: lite' >"$d/expected"
  for source in startup resume compact clear fork; do
    write_input "$d/in.json" "$source" "$OVERSEER" -
    run_hook "$d/in.json" LPF_TIER=lite
    expect_context "$source, overseer, lite, no scratchpad_dir" "$d/expected"
    write_input "$d/in.json" "$source" "$OVERSEER" ""
    run_hook "$d/in.json" LPF_TIER=lite
    expect_context "$source, overseer, lite, empty scratchpad_dir" "$d/expected"
    printf '{"source":"%s","agent_type":"%s","scratchpad_dir":42}' "$source" "$OVERSEER" >"$d/in.json"
    run_hook "$d/in.json" LPF_TIER=lite
    expect_context "$source, overseer, lite, scratchpad_dir 42" "$d/expected"
    write_input "$d/in.json" "$source" "$OVERSEER" -
    run_hook "$d/in.json" LPF_TIER=full
    expect_silent "$source, overseer, LPF_TIER full, no scratchpad_dir"
    for agent in "" "little-planet-factory:manager"; do
      write_input "$d/in.json" "$source" "$agent" -
      run_hook "$d/in.json" LPF_TIER=lite
      expect_silent "$source, agent_type '$agent', lite, no scratchpad_dir"
    done
  done
  # A bad ledger still suppresses all output, the tier line included.
  mkdir "$d/factory-ledger.md"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  run_hook "$d/in.json" LPF_TIER=lite
  expect_silent "ledger is a directory, overseer, lite"
}

overseer_lite_compact_announces_tier_then_injects() {
  d=$(new_dir)
  write_tricky_ledger "$d/factory-ledger.md"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  {
    printf 'Factory ledger for this session: %s/factory-ledger.md\nFactory tier: lite\n\n' "$d"
    write_block "$d/block" compaction "$d/factory-ledger.md" "$d/factory-ledger.md"
    cat "$d/block"
  } >"$d/expected"
  run_hook "$d/in.json" LPF_TIER=lite
  expect_context "overseer compact, lite" "$d/expected"
}

overseer_lite_oversized_stays_under_cap() {
  d=$(new_dir)
  ledger="$d/factory-ledger.md"
  printf 'Factory ledger re-injected after compaction: %s\n%s\n---\n' "$ledger" "$FOLLOW_LINE" >"$d/header"
  header_len=$(wc -c <"$d/header" | tr -d ' ')
  # Fits alone at exactly 9,000, so the announcement and tier line push it over.
  repeat_char $((9000 - header_len)) x >"$ledger"
  write_input "$d/in.json" compact "$OVERSEER" "$d"
  {
    printf 'Factory ledger for this session: %s\nFactory tier: lite\n\n' "$ledger"
    write_pointer "$d/pointer" "$ledger" $((9000 - header_len))
    cat "$d/pointer"
  } >"$d/expected"
  run_hook "$d/in.json" LPF_TIER=lite
  expect_context "overseer, lite, oversized" "$d/expected"
  [ "$(cat "$CTXLEN")" -lt 10000 ] || fail "context is $(cat "$CTXLEN") characters"
}

# Runs last: checks every non-empty stdout any earlier test produced.
output_is_valid_json() {
  if [ "$OUTPUT_COUNT" -eq 0 ]; then
    fail "no outputs were recorded, so nothing was checked"
    return
  fi
  for file in "$WORK"/outputs/*.json; do
    cp "$file" "$OUT"
    extract_context || fail "$(basename "$file"): $(cat "$WORK/extract-error")"
  done
  echo "    checked $OUTPUT_COUNT outputs"
}

run_test hooks_json_registers_session_start_for_all_sources
run_test non_overseer_without_ledger_outputs_nothing
run_test overseer_startup_announces_path
run_test compact_injects_existing_ledger_without_agent_type
run_test resume_injects_existing_ledger
run_test overseer_compact_announces_then_injects
run_test startup_and_clear_do_not_inject_contents
run_test empty_ledger_is_not_injected
run_test ledger_directory_is_not_injected
run_test oversized_ledger_injects_pointer_only
run_test no_scratchpad_outputs_nothing
run_test multibyte_oversized_ledger_reports_bytes
run_test fifo_ledger_does_not_hang
run_test symlinked_ledger_behavior
run_test garbage_stdin_is_silent
run_test empty_stdin_is_silent
run_test invalid_utf8_ledger_is_silent
run_test unreadable_ledger_is_silent
run_test missing_node_is_silent
run_test hook_writes_nothing
run_test overseer_lite_announces_tier
run_test lite_tier_line_is_overseer_only
run_test lite_overseer_without_scratchpad_gets_tier_only
run_test overseer_lite_compact_announces_tier_then_injects
run_test overseer_lite_oversized_stays_under_cap
run_test output_is_valid_json

echo
echo "$PASSED passed, $FAILED failed"
[ "$FAILED" -eq 0 ]
