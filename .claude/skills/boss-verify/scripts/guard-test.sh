#!/usr/bin/env bash
# Negative-guard test for bin/boss-send-keys: given a guard string that cannot be on the worker's
# screen, it must print NOT SENT, exit 3 and send nothing.
#
# Usage: guard-test.sh <worker-name>
#   Run it only after the user has confirmed <worker-name> as a safe target (SKILL.md step 4). The one
#   token handed to boss-send-keys is key:left, a no-op at an idle prompt. It would reach the worker
#   only if the guard check were broken, which is the thing under test, so the script refuses unless
#   the worker is idle at a plain prompt (registry state idle, no menu cursor or confirmation prompt
#   on its screen).
# Exit: 0 = PASS, 1 = FAIL (if the output says a key was sent, tell the user at once),
#       2 = could not run, or inconclusive, 4 = refused (worker not idle at a plain prompt)
set -u
. "$(dirname "$(readlink -f "$0")")/../../../../bin/lib.sh"
name=${1:-}
[ -n "$name" ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }
boss_pid >/dev/null || { echo "ERROR: no live boss (boss.pid is missing or stale)" >&2; exit 2; }
pid=$(pid_for "$name") || exit 2
is_claude "$pid" || { echo "ERROR: $name's claude process is gone" >&2; exit 2; }

state=$(jq -r .state "$(sess_file "$pid")")
[ "$state" = idle ] || { echo "REFUSED: $name is '$state', not idle; pick a worker sitting at an empty prompt" >&2; exit 4; }
before=$(screen_text "$pid") || { echo "ERROR: cannot read $name's screen (no reachable window)" >&2; exit 2; }
if grep -qE '❯ [0-9]+\.|to proceed\?' <<<"$before"; then
  echo "REFUSED: $name's screen shows a menu or confirmation prompt" >&2; exit 4
fi

guard="boss-verify-no-such-prompt-$$-$(date +%s%N)"
out=$("$BOSS_DIR/bin/boss-send-keys" "$name" "$guard" key:left 2>&1); rc=$?
after=$(screen_text "$pid" 2>/dev/null)

if [ "$rc" -eq 3 ] && grep -q '^NOT SENT' <<<"$out" && ! grep -q '^Sent to' <<<"$out"; then
  echo "PASS: boss-send-keys printed NOT SENT and exited 3 for a guard that is not on $name's screen"
  [ "$before" = "$after" ] || echo "note: $name's screen changed while the test ran (it may have produced output on its own)"
  exit 0
fi
if [ "$rc" -eq 0 ] || grep -q '^Sent to' <<<"$out"; then
  echo "FAIL: boss-send-keys SENT key:left to $name although the guard was not on its screen. Its guard check is broken; tell the user now."
  exit 1
fi
echo "INCONCLUSIVE: boss-send-keys exited $rc: $(head -n1 <<<"$out" | cut -c1-200)" >&2
exit 2
