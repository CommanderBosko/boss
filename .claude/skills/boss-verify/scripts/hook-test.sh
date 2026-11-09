#!/usr/bin/env bash
# boss-hook invariant test: bin/boss-hook must print NOTHING on stdout and exit 0 for every hook
# event except SessionStart, whose only output is the briefing JSON. Output on PermissionRequest or
# PreToolUse can approve or deny a prompt, and exit 2 blocks one (CLAUDE.md, "Invariant").
#
# Hermetic: the hook runs against a scratch XDG_RUNTIME_DIR, with two stand-in processes named
# "claude" (a sleeping script): a boss whose cwd is the boss folder, and a worker whose cwd is a
# scratch folder. Neither has a kitty or herdr environment, so the hook's label calls cannot touch a
# real window, and no real registry or event log is read or written. The two pids must differ: the
# hook exits at once when the two are the same, which would make every event look silent.
# Usage: hook-test.sh    exit 0 = invariant holds, 1 = violated, 2 = setup failed (nothing verified)
set -u
root=$(cd "$(dirname "$(readlink -f "$0")")/../../../.." && pwd -P)
hook=$root/bin/boss-hook
[ -x "$hook" ] || { echo "ERROR: $hook is missing or not executable"; exit 2; }
command -v jq >/dev/null || { echo "ERROR: jq not found"; exit 2; }

S=$(mktemp -d "${TMPDIR:-/tmp}/boss-verify.XXXXXX") || { echo "ERROR: mktemp failed"; exit 2; }
pids=()
cleanup() {
  local p
  for p in "${pids[@]}"; do pkill -P "$p" 2>/dev/null; kill "$p" 2>/dev/null; done
  rm -rf "$S"
}
trap cleanup EXIT

# A script named claude, run with a direct interpreter shebang so /proc/<pid>/comm reads "claude".
printf '#!%s\nsleep 600 &\nwait\n' "$(command -v bash)" >"$S/claude" && chmod +x "$S/claude"
start_fake() { # start_fake <cwd>: prints the pid once its comm reads "claude"
  local p
  p=$(cd "$1" || exit 1; env -i PATH="$PATH" "$S/claude" </dev/null >/dev/null 2>&1 & echo $!)
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ "$(cat "/proc/$p/comm" 2>/dev/null)" = claude ] && { echo "$p"; return 0; }
    sleep 0.2
  done
  return 1
}

mkdir -p "$S/work/fake-worker" "$S/run/claude-boss"
bpid=$(start_fake "$root") || { echo "ERROR: could not start the stand-in boss process"; exit 2; }
pids+=("$bpid")
wpid=$(start_fake "$S/work/fake-worker") || { echo "ERROR: could not start the stand-in worker process"; exit 2; }
pids+=("$wpid")
[ "$(readlink "/proc/$bpid/cwd")" = "$root" ] || { echo "ERROR: stand-in boss is not in $root"; exit 2; }
echo "$bpid" >"$S/run/claude-boss/boss.pid"

# --- helpers -----------------------------------------------------------------------------------
n=0 fails=0
pass() { n=$((n + 1)); echo "  ok   $1"; }
fail() { n=$((n + 1)); fails=$((fails + 1)); echo "  FAIL $1: $2"; }
note_err() { [ -s "$S/err" ] && echo "         (stderr, not a failure: $(head -n1 "$S/err" | cut -c1-100))"; return 0; }

hook_run() { # hook_run <json> [pid]: stdout lands in $S/out, stderr in $S/err, exit code in $rc
  printf '%s' "$1" | env XDG_RUNTIME_DIR="$S/run" BOSS_HOOK_PID="${2:-$wpid}" "$hook" >"$S/out" 2>"$S/err"
  rc=$?
}
silent() { # silent <label> <json> [pid]: stdout must be empty and the exit code 0
  hook_run "$2" "${3:-}"
  if [ "$rc" -ne 0 ]; then fail "$1" "exit $rc (a non-zero exit can block or deny the call)"
  elif [ -s "$S/out" ]; then fail "$1" "stdout has $(wc -c <"$S/out") bytes, want none: $(head -c 100 "$S/out" | tr '\n' ' ')"
  else pass "$1"; fi
  note_err
}
briefing() { # briefing <label> <json>: stdout must be exactly the SessionStart briefing JSON
  hook_run "$2" "${3:-}"
  if [ "$rc" -ne 0 ]; then fail "$1" "exit $rc"
  elif ! jq -e '(keys == ["hookSpecificOutput"]) and (.hookSpecificOutput |
        ((keys | sort) == ["additionalContext", "hookEventName"]) and .hookEventName == "SessionStart"
        and (.additionalContext | type == "string" and length > 0))' "$S/out" >/dev/null 2>&1; then
    fail "$1" "stdout is not exactly the SessionStart briefing JSON"
  else pass "$1"; fi
  note_err
}
ev() { # ev <event> [extra json members]; printf '%s', never echo: the tool shell is zsh
  printf '{"hook_event_name":"%s","session_id":"boss-verify-fake"%s}' "$1" "${2:+,$2}"
}

# --- static scan: no decision-style output, no exit 2 ------------------------------------------
echo "-- static scan of bin/boss-hook --"
pat='permissionDecision|"decision"|decision:|behavior|updatedInput|stopReason|"continue"|exit[[:space:]]+2'
hits=$(grep -nE "$pat" "$hook" | grep -vE '^[0-9]+:[[:space:]]*#')
if [ -n "$hits" ]; then fail "static: decision-style output or exit 2" "$(head -n3 <<<"$hits" | tr '\n' ' ')"
else pass "static: no decision output, no exit 2"; fi
emitters=$(grep -v '^[[:space:]]*#' "$hook" | grep -c 'hookSpecificOutput')
if [ "$emitters" -ne 1 ]; then fail "static: hookSpecificOutput emitters" "want exactly 1 (SessionStart's), found $emitters"
else pass "static: one hookSpecificOutput emitter"; fi

# --- live boss, a worker's session (state carries from one case to the next) -------------------
echo "-- worker session under a live boss --"
menu='"tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Pick one?","options":[{"label":"A"},{"label":"B"}]}]}'
briefing "SessionStart (startup)"                  "$(ev SessionStart '"source":"startup"')"
silent   "UserPromptSubmit (relayed message)"      "$(ev UserPromptSubmit '"prompt":"<cross-session-message from=\"boss\">run the tests</cross-session-message>"')"
silent   "PreToolUse (AskUserQuestion menu)"       "$(ev PreToolUse "$menu")"
silent   "PermissionRequest (menu already announced)" "$(ev PermissionRequest "$menu")"
silent   "PostToolUse (resolves the menu)"         "$(ev PostToolUse '"tool_name":"AskUserQuestion","tool_input":{},"tool_response":{}')"
silent   "PostToolUse (already working)"           "$(ev PostToolUse '"tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":{}')"
silent   "PreToolUse (ExitPlanMode plan)"          "$(ev PreToolUse '"tool_name":"ExitPlanMode","tool_input":{"plan":"1. Do a thing\n2. Do another"}')"
silent   "PermissionRequest (Bash command)"        "$(ev PermissionRequest '"tool_name":"Bash","tool_input":{"command":"chmod -R 700 x"}')"
silent   "PostToolUse (resolves the permission)"   "$(ev PostToolUse '"tool_name":"Bash","tool_input":{"command":"chmod -R 700 x"},"tool_response":{}')"
silent   "Stop"                                    "$(ev Stop)"
silent   "Notification (permission_prompt)"        "$(ev Notification '"notification_type":"permission_prompt","message":"Claude needs your permission"')"
silent   "Notification (idle_prompt)"              "$(ev Notification '"notification_type":"idle_prompt","message":"Claude is waiting"')"
silent   "Stop (a prompt still open)"              "$(ev Stop)"
silent   "PreToolUse (plain Bash)"                 "$(ev PreToolUse '"tool_name":"Bash","tool_input":{"command":"ls"}')"
briefing "SessionStart (compact)"                  "$(ev SessionStart '"source":"compact"')"
briefing "SessionStart (clear)"                    "$(ev SessionStart '"source":"clear"')"
briefing "SessionStart (resume)"                   "$(ev SessionStart '"source":"resume"')"
silent   "SessionEnd (clear)"                      "$(ev SessionEnd '"reason":"clear"')"
silent   "SessionEnd (exit)"                       "$(ev SessionEnd '"reason":"other"')"

# --- the boss's own session, and no live boss: the hook must stay inert ------------------------
echo "-- the boss's own session --"
silent "SessionStart from the boss's pid"          "$(ev SessionStart '"source":"startup"')" "$bpid"
silent "PreToolUse from the boss's pid"            "$(ev PreToolUse '"tool_name":"Bash","tool_input":{"command":"ls"}')" "$bpid"

echo "-- no live boss --"
extra='"source":"startup","tool_name":"Bash","tool_input":{},"prompt":"hi","reason":"other"'
rm -f "$S/run/claude-boss/boss.pid"
for e in PermissionRequest PreToolUse PostToolUse Stop Notification SessionEnd UserPromptSubmit SessionStart; do
  silent "$e (no boss.pid)" "$(ev "$e" "$extra")"
done
echo 999999999 >"$S/run/claude-boss/boss.pid"
silent "SessionStart (stale boss.pid)"             "$(ev SessionStart '"source":"startup"')"
silent "PreToolUse (stale boss.pid)"               "$(ev PreToolUse '"tool_name":"Bash","tool_input":{}')"

# --- the silent results only mean something if the hook did real work earlier ------------------
echo "-- coverage --"
log=$S/run/claude-boss/events.jsonl
if [ -s "$log" ]; then pass "event log written (events: $(jq -r .event "$log" | sort -u | tr '\n' ' '))"
else fail "event log" "events.jsonl is empty, so the hook did no work and the silent results above prove nothing"; fi

echo
if [ "$fails" -eq 0 ]; then
  echo "RESULT: PASS ($n cases: stdout empty and exit 0 on every event except SessionStart)"
  exit 0
fi
echo "RESULT: FAIL ($fails of $n cases failed)"
exit 1
