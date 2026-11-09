#!/usr/bin/env bash
# Full verification battery for the boss's bin/ scripts, hooks and .claude/settings.json.
# Usage: verify.sh               check every file in bin/ (default)
#        verify.sh --changed     check only bin/ files git reports as modified, staged or untracked
#        verify.sh <name>...     check the named files (boss-hook or bin/boss-hook)
# Checks: 1 bash -n, 2 jq empty on settings.json, 3 shellcheck -x -S warning, 4 boss-hook invariant
# (hook-test.sh; always runs, because the hook sources lib.sh), 5 live read-only (boss-status, boss-screen).
# The keys test (guard-test.sh) is separate: it needs the user's OK on a target worker.
# Exit: 0 = nothing failed (a SKIP is not a pass), 1 = a check FAILed or ERRORed, 2 = bad usage
set -u
here=$(dirname "$(readlink -f "$0")")
root=$(cd "$here/../../../.." && pwd -P)
cd "$root" || exit 2

# --- which files -------------------------------------------------------------------------------
sel=()
case ${1:-} in
  "")
    for f in bin/*; do [ -f "$f" ] && sel+=("$f"); done ;;
  --changed)
    while IFS= read -r f; do [ -f "$f" ] && sel+=("$f"); done < <(
      { git diff --name-only --relative HEAD -- bin; git ls-files --others --exclude-standard -- bin; } 2>/dev/null | sort -u) ;;
  -*)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2 ;;
  *)
    for n in "$@"; do
      f=bin/${n#bin/}
      [ -f "$f" ] || { echo "no such file: $f" >&2; exit 2; }
      sel+=("$f")
    done ;;
esac

RES=() FAILS=0
record() { # record <id> <check> <PASS|FAIL|SKIP|ERROR> <detail>
  RES+=("$1|$2|$3|$4")
  case $3 in FAIL|ERROR) FAILS=$((FAILS + 1)) ;; esac
}

# True unless the file's shebang names something other than bash or sh (lib.sh has no shebang).
is_bash() {
  local l; l=$(head -n 1 "$1")
  case $l in
    '#!'*) case $l in *bash*|*/sh|*' sh') return 0 ;; *) return 1 ;; esac ;;
    *) return 0 ;;
  esac
}

# --- 1. bash -n --------------------------------------------------------------------------------
echo "== 1. bash -n on ${#sel[@]} file(s) =="
shfiles=() bad=0
for f in "${sel[@]}"; do
  if ! is_bash "$f"; then echo "  skip $f (shebang is not bash)"; continue; fi
  shfiles+=("$f")
  if err=$(bash -n "$f" 2>&1); then
    echo "  ok   $f"
  else
    echo "  FAIL $f"; printf '%s\n' "$err" | sed 's/^/         /'; bad=$((bad + 1))
  fi
done
if [ ${#shfiles[@]} -eq 0 ]; then record 1 "bash -n" SKIP "no bin/ scripts selected"
elif [ "$bad" -gt 0 ]; then record 1 "bash -n" FAIL "$bad of ${#shfiles[@]} scripts have syntax errors"
else record 1 "bash -n" PASS "${#shfiles[@]} scripts"; fi

# --- 2. settings.json --------------------------------------------------------------------------
echo "== 2. jq empty .claude/settings.json =="
if err=$(jq empty "$root/.claude/settings.json" 2>&1); then
  echo "  ok   valid JSON"; record 2 "settings.json" PASS "valid JSON"
else
  printf '%s\n' "$err" | sed 's/^/  /'; record 2 "settings.json" FAIL "$(head -n1 <<<"$err")"
fi

# --- 3. shellcheck -----------------------------------------------------------------------------
# -s bash: bin/lib.sh has no shebang, which would otherwise be SC2148 (an error at any severity).
echo "== 3. shellcheck -x -S warning =="
if [ ${#shfiles[@]} -eq 0 ]; then
  record 3 "shellcheck" SKIP "no bin/ scripts selected"
else
  if command -v shellcheck >/dev/null 2>&1; then sc=(shellcheck)
  else sc=(timeout 600 nix shell nixpkgs#shellcheck -c shellcheck); fi
  out=$("${sc[@]}" -s bash -x -S warning "${shfiles[@]}" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  ok   no findings"; record 3 "shellcheck" PASS "${#shfiles[@]} scripts clean"
  elif grep -q '^In .* line [0-9]*:' <<<"$out"; then
    printf '%s\n' "$out" | head -n 60 | sed 's/^/  /'
    record 3 "shellcheck" FAIL "$(grep -c '^In .* line [0-9]*:' <<<"$out") finding(s); codes: $(grep -o 'SC[0-9]*' <<<"$out" | sort -u | tr '\n' ' ')"
  else
    printf '%s\n' "$out" | head -n 10 | sed 's/^/  /'
    record 3 "shellcheck" SKIP "shellcheck did not run (exit $rc): $(head -n1 <<<"$out" | cut -c1-100)"
  fi
fi

# --- 4. boss-hook invariant --------------------------------------------------------------------
echo "== 4. boss-hook invariant (hook-test.sh) =="
out=$("$here/hook-test.sh" 2>&1); rc=$?
printf '%s\n' "$out" | sed 's/^/  /'
detail=$(grep '^RESULT: ' <<<"$out" | tail -n 1 | sed 's/^RESULT: //')
case $rc in
  0) record 4 "boss-hook invariant" PASS "$detail" ;;
  1) record 4 "boss-hook invariant" FAIL "$detail" ;;
  *) record 4 "boss-hook invariant" ERROR "hook-test.sh could not run (exit $rc); nothing verified" ;;
esac

# --- 5. live read-only checks ------------------------------------------------------------------
# Only line counts are shown: what boss-status and boss-screen print is worker text, which is data.
echo "== 5. live read-only checks =="
. "$root/bin/lib.sh"
if ! boss_pid >/dev/null; then
  echo "  skip no live boss (boss.pid missing or stale); boss-status would register this session as a worker"
  record 5 "live read-only" SKIP "no live boss"
else
  s_out=$("$root/bin/boss-status" 2>&1); s_rc=$?
  echo "  boss-status: exit $s_rc, $(wc -l <<<"$s_out") line(s)"
  w=""
  for f in "$SESS_DIR"/*.json; do
    [ -f "$f" ] || continue
    is_claude "$(basename "$f" .json)" || continue
    if [ "$(jq -r '(.herdr // .kitty) != null' "$f")" = true ]; then w=$(jq -r .name "$f"); break; fi
  done
  if [ -z "$w" ]; then
    echo "  boss-screen: skipped, no live worker with a reachable window"
    if [ "$s_rc" -eq 0 ]; then record 5 "live read-only" SKIP "boss-status ok; no reachable worker for boss-screen"
    else record 5 "live read-only" FAIL "boss-status exit $s_rc"; fi
  else
    c_out=$("$root/bin/boss-screen" "$w" 2>&1); c_rc=$?
    echo "  boss-screen $w: exit $c_rc, $(wc -l <<<"$c_out") line(s)"
    if [ "$s_rc" -eq 0 ] && [ "$c_rc" -eq 0 ]; then record 5 "live read-only" PASS "boss-status and boss-screen $w exit 0"
    else record 5 "live read-only" FAIL "boss-status exit $s_rc, boss-screen $w exit $c_rc"; fi
  fi
fi

# --- summary -----------------------------------------------------------------------------------
echo
echo "== Summary =="
skips=0
for r in "${RES[@]}"; do
  IFS='|' read -r id name status detail <<<"$r"
  printf '  %s  %-20s %-6s %s\n' "$id" "$name" "$status" "$detail"
  [ "$status" = SKIP ] && skips=$((skips + 1))
done
echo "  6  negative-guard test  NOT RUN  needs the user's OK on a worker (guard-test.sh)"
if [ "$FAILS" -gt 0 ]; then
  echo "RESULT: FAIL ($FAILS check(s) failed)"; exit 1
elif [ "$skips" -gt 0 ]; then
  echo "RESULT: PASS, but $skips check(s) were skipped and are NOT verified"; exit 0
fi
echo "RESULT: PASS"
exit 0
