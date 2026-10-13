#!/usr/bin/env bash
# Read-only check for definition-of-done item 1: the registry lists exactly the claude processes
# `pgrep -x claude` shows, minus the boss, each with the right folder and name. Also prints each
# worker's kitty background (item 2: same folder, same color) and focus (item 3: never focused).
# Usage: check-registry.sh    exit 0 = match, 1 = mismatch, 2 = no live boss
set -u
. "$(dirname "$(readlink -f "$0")")/../../../../bin/lib.sh"
bp=$(boss_pid) || { echo "no live boss (boss.pid is missing or stale)" >&2; exit 2; }

procs=$(pgrep -x claude | grep -vx "$bp")
regs=$(for f in "$SESS_DIR"/*.json; do [ -f "$f" ] && basename "$f" .json; done)

fail=0 rows=""
for pid in $(printf '%s\n%s\n' "$procs" "$regs" | sort -nu); do
  f=$(sess_file "$pid") name=- folder=- bg=- focused=- check=ok
  live_cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
  if ! printf '%s\n' "$procs" | grep -qx "$pid"; then
    check=STALE
  elif [ ! -f "$f" ]; then
    check=UNREGISTERED; folder=$live_cwd
  else
    name=$(jq -r .name "$f"); folder=$(jq -r .cwd "$f")
    to=$(jq -r '.kitty.to // empty' "$f"); win=$(jq -r '.kitty.win // empty' "$f")
    if [ "$folder" != "$live_cwd" ]; then check="WRONG-FOLDER(live:$live_cwd)"
    elif [ "${name%-[0-9]*}" != "$(base_name "$live_cwd")" ]; then check=WRONG-NAME
    fi
    if [ -n "$to" ] && [ -n "$win" ]; then
      bg=$(kitten @ --to "$to" get-colors --match "id:$win" 2>/dev/null | awk '$1 == "background" {print $2}')
      focused=$(kitten @ --to "$to" ls --match "id:$win" 2>/dev/null |
        jq -r --argjson w "$win" '[.[].tabs[].windows[] | select(.id == $w) | .is_focused | tostring] | first // "?"')
    fi
  fi
  [ "$check" = ok ] || fail=1
  rows+="$pid	$name	${folder/#$HOME/\~}	${bg:--}	${focused:--}	$check"$'\n'
done

{ printf 'PID\tNAME\tFOLDER\tBACKGROUND\tFOCUSED\tCHECK\n'; printf '%s' "$rows"; } | column -t -s $'\t'
if [ "$fail" = 0 ]; then
  echo "OK: registry matches pgrep -x claude (boss pid $bp excluded)"
else
  echo "MISMATCH: see the CHECK column"
fi
exit "$fail"
