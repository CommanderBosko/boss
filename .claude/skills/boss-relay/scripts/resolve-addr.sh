#!/usr/bin/env bash
# Read-only: resolve a worker's name or nickname to the address SendMessage needs.
# SendMessage rejects a bare session name ("No agent is named 'NixOS' exactly"); the peer address
# `uds:<run dir>/cc-socks/<claude pid>.sock` always works, and the registry knows the pid.
# Usage: resolve-addr.sh <name-or-nickname>
#   stdout  the address and nothing else, e.g. uds:/run/user/1000/cc-socks/13638.sock
#   stderr  one "resolved:" line (exact session name + pid), or the reason it failed
#   exit    0 resolved
#           1 no live session by that name (stderr lists the live names)
#           2 more than one live session matches (stderr lists them)
#           3 usage error, or no worker registry (the boss isn't running)
#           4 matched, but that pid has no peer socket to send to
# Nicknames come from the session-aliases memory (lines like `- "bs" or "BS" → blueprint-smith`);
# override the file with BOSS_ALIASES. Matching is exact first, then case-insensitive, so
# "nixos" finds NixOS but "farmer" never matches farmer-2.
set -u
. "$(dirname "$(readlink -f "$0")")/../../../../bin/lib.sh"

want=${1:-}
[ -n "$want" ] || { echo "usage: resolve-addr.sh <name-or-nickname>" >&2; exit 3; }
[ -d "$SESS_DIR" ] || { echo "no worker registry at $SESS_DIR (is the boss running?)" >&2; exit 3; }

ALIASES=${BOSS_ALIASES:-$HOME/.claude/projects/$(printf %s "$BOSS_DIR" | tr / -)/memory/session-aliases.md}

# alias_target <lowercased input>: print the real session name for a nickname, or fail.
alias_target() {
  local line left right a
  if [ -f "$ALIASES" ]; then
    while IFS= read -r line; do
      case $line in "- "*"→"*) ;; *) continue ;; esac
      left=${line%%→*}
      right=$(printf '%s' "${line#*→}" | sed -E 's/^[[:space:]`]+//; s/[[:space:]`(].*$//')
      [ -n "$right" ] || continue
      while IFS= read -r a; do
        [ "${a,,}" = "$1" ] && { printf '%s\n' "$right"; return 0; }
      done < <(printf '%s' "$left" | grep -o '"[^"]*"' | tr -d '"')
    done <"$ALIASES"
  fi
  case $1 in bs) echo blueprint-smith ;; *) return 1 ;; esac # fallback if the memory file is gone
}

target=$(alias_target "${want,,}") || target=$want

# The live registry: only entries whose pid is still a claude process.
pids=() names=()
shopt -s nullglob
for f in "$SESS_DIR"/*.json; do
  pid=$(basename "$f" .json)
  is_claude "$pid" || continue
  pids+=("$pid"); names+=("$(jq -r '.name // empty' "$f")")
done

live=${names[*]:-}
match=()
for i in "${!names[@]}"; do [ "${names[$i]}" = "$target" ] && match+=("$i"); done
if [ ${#match[@]} -eq 0 ]; then
  for i in "${!names[@]}"; do [ "${names[$i],,}" = "${target,,}" ] && match+=("$i"); done
fi

via=""
[ "$target" != "$want" ] && via=" (nickname for $target)"

if [ ${#match[@]} -eq 0 ]; then
  echo "no live worker session named '$want'$via. Live sessions: ${live:-(none)}" >&2
  exit 1
fi
if [ ${#match[@]} -gt 1 ]; then
  list=""
  for i in "${match[@]}"; do list+="${names[$i]} (pid ${pids[$i]}) "; done
  echo "more than one live session matches '$want'$via: $list" >&2
  exit 2
fi

pid=${pids[${match[0]}]} name=${names[${match[0]}]}
[ -S "$RUN_DIR/cc-socks/$pid.sock" ] || { echo "$name (pid $pid) has no peer socket at $RUN_DIR/cc-socks/$pid.sock" >&2; exit 4; }
echo "resolved: '$want'$via -> $name (pid $pid)" >&2
peer_addr "$pid"
