#!/usr/bin/env bash
# Read-only preflight for boss-acceptance step 1: are there enough kitty workers (2+, one in a git
# repo), and does `claude --version` match the version on CLAUDE.md's Known keys line?
# Usage: preflight.sh    exit 0 = ready, 1 = not enough workers (stop), 2 = no live boss,
#                        3 = ready but the version changed (key mappings unverified until 4a-4c pass)
set -u
. "$(dirname "$(readlink -f "$0")")/../../../../bin/lib.sh"
boss_pid >/dev/null || { echo "no live boss (boss.pid is missing or stale)" >&2; exit 2; }

workers=0 git_workers=""
for f in "$SESS_DIR"/*.json; do
  [ -f "$f" ] || continue
  pid=$(basename "$f" .json)
  is_claude "$pid" || continue
  [ -n "$(jq -r '.kitty.to // empty' "$f")" ] || continue
  workers=$((workers + 1))
  cwd=$(jq -r .cwd "$f")
  git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1 && git_workers+="$(jq -r .name "$f") "
done
echo "kitty workers: $workers; in a git repo: ${git_workers:-none}"

live=$(claude --version 2>/dev/null | awk '{print $1}')
known=$(sed -n 's/^\*\*Known keys\*\* (verified on Claude Code \([^)]*\)).*/\1/p' "$BOSS_DIR/CLAUDE.md" | head -1)
echo "claude --version: ${live:-?}; Known keys verified on: ${known:-?}"

if [ "$workers" -lt 2 ] || [ -z "$git_workers" ]; then
  echo "NOT READY: need 2+ kitty workers, one of them in a git repo"
  exit 1
fi
if [ -z "$live" ] || [ "$live" != "$known" ]; then
  echo "READY, VERSION CHANGED: treat every key mapping as unverified until items 4a-4c pass"
  exit 3
fi
echo "READY"
