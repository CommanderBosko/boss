#!/usr/bin/env bash
# Read-only stale-reference finder for boss-doc-sweep (step 2, and again in step 5 to confirm zero hits).
# Case-insensitive fixed-string search for the old term(s) over bin/, CLAUDE.md, README.md,
# project-state.md, session-summary.md, mods/, .claude-plugin/, .claude/settings.json, .claude/skills/,
# docs/ and the project's memory dir, grouped by file. Also lists tracked or memory FILE NAMES that
# contain a term (dead scripts and plugin folders show up there even when their contents don't).
# Usage: find-stale.sh [--include-acceptance] [--] <term>...
#   Terms are OR'd and matched as fixed strings, so 'kitten @' or 'boss-rows' need no escaping.
#   Skipped by default: docs/acceptance-*.md (dated records; --include-acceptance scans them) and this
#   skill's own folder (its text uses example terms). Scan paths that don't exist are skipped.
#   Env overrides: BOSS_DIR (default: the project this script lives in), MEMORY_DIR (default: that
#   project's ~/.claude/projects/<slug>/memory).
# Exit 0 = no hits (clean), 1 = hits found, 2 = usage error or bad BOSS_DIR.
set -u

usage() { echo "usage: find-stale.sh [--include-acceptance] [--] <term>..." >&2; exit 2; }

include_acc=0
while [ $# -gt 0 ]; do
  case $1 in
    --include-acceptance) include_acc=1; shift ;;
    --) shift; break ;;
    -h|--help|-*) usage ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || usage
pat=()
for t in "$@"; do
  [ -n "$t" ] || { echo "empty term would match every line" >&2; exit 2; }
  pat+=(-e "$t")
done

BOSS_DIR=${BOSS_DIR:-$(cd "$(dirname "$(readlink -f "$0")")/../../../.." && pwd)}
MEMORY_DIR=${MEMORY_DIR:-$HOME/.claude/projects/${BOSS_DIR//\//-}/memory}
cd "$BOSS_DIR" 2>/dev/null || { echo "BOSS_DIR not found: $BOSS_DIR" >&2; exit 2; }

targets=() missing=()
for p in bin CLAUDE.md README.md project-state.md session-summary.md mods .claude-plugin \
         .claude/settings.json .claude/skills docs "$MEMORY_DIR"; do
  if [ -e "$p" ]; then targets+=("$p"); else missing+=("$p"); fi
done

own='^\.claude/skills/boss-doc-sweep/'
acc='^docs/acceptance-[^/]*\.md(:|$)'
# Drops this skill's own folder, and the dated acceptance records unless --include-acceptance.
keep() { grep -v -E "$own" | { if [ "$include_acc" = 1 ]; then cat; else grep -v -E "$acc"; fi; }; }

echo "terms: $*"
echo "scanned: ${targets[*]}"
[ ${#missing[@]} -eq 0 ] || echo "not present (skipped): ${missing[*]}"
echo

# Content hits: path:line:text, sorted by file then line, grouped under one header per file.
raw=$(grep -rnHIiF --exclude-dir=.git --exclude-dir=node_modules "${pat[@]}" -- "${targets[@]}" 2>/dev/null)
kept=$(printf '%s\n' "$raw" | keep | sort -s -t: -k1,1 -k2,2n)
if [ -n "$kept" ]; then
  printf '%s\n' "$kept" | awk '
    {
      i = index($0, ":"); f = substr($0, 1, i - 1); rest = substr($0, i + 1)
      j = index(rest, ":"); n = substr(rest, 1, j - 1); t = substr(rest, j + 1)
      sub(/^[ \t]+/, "", t); if (length(t) > 200) t = substr(t, 1, 200) "..."
      if (!(f in cnt)) order[++nf] = f
      cnt[f]++; buf[f] = buf[f] sprintf("   %5s: %s\n", n, t)
    }
    END { for (k = 1; k <= nf; k++) { f = order[k]; printf "== %s (%d)\n%s", f, cnt[f], buf[f] } }'
  total=$(printf '%s\n' "$kept" | grep -c .)
  files=$(printf '%s\n' "$kept" | cut -d: -f1 | sort -u | grep -c .)
else
  total=0 files=0
fi

if [ "$include_acc" = 0 ]; then
  skipped=$(printf '%s\n' "$raw" | grep -E "$acc" | cut -d: -f1 | sort | uniq -c | awk '{printf "%s (%s) ", $2, $1}')
  [ -z "$skipped" ] || { echo; echo "skipped dated records (pass --include-acceptance to scan): $skipped"; }
fi

# File names containing a term: delete or rename candidates.
names=$({ git ls-files 2>/dev/null; [ -d "$MEMORY_DIR" ] && ls -1 "$MEMORY_DIR" 2>/dev/null | sed "s|^|$MEMORY_DIR/|"; } |
  grep -iF "${pat[@]}" | keep)
if [ -n "$names" ]; then
  echo
  echo "file names containing a term (delete or rename candidates):"
  printf '%s\n' "$names" | sed 's/^/   /'
fi

echo
if [ "$total" -eq 0 ] && [ -z "$names" ]; then
  echo "CLEAN: no hits"
  exit 0
fi
echo "HITS: $total line(s) in $files file(s)"
exit 1
