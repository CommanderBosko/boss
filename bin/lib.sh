# Shared helpers for the boss scripts. Sourced, never executed.
#
# State lives in $XDG_RUNTIME_DIR/claude-boss (tmpfs, private to this user):
#   boss.pid             pid of the live boss claude process (stale if that pid is gone)
#   events.jsonl         append-only event log written by boss-hook, tailed by boss-watch
#   sessions/<pid>.json  one registry entry per live worker claude process
# Workers are keyed by claude pid, not session_id, because /clear changes the
# session_id but keeps the process (and its peer socket) alive.

BOSS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
RUN_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
STATE_DIR=$RUN_DIR/claude-boss
SESS_DIR=$STATE_DIR/sessions
EVENTS=$STATE_DIR/events.jsonl
LOCK=$STATE_DIR/.lock
BOSS_COLOR='#ffd700'
# Distinct on a black background; a folder hashes to one of these unless colors.conf overrides it.
PALETTE=('#e06c75' '#f0a050' '#e5c07b' '#a6e22e' '#4ec98a' '#2ab7a9' '#61afef' '#8c7cf0' '#c678dd' '#ff79c6' '#c08a5a' '#a0a8b8')

is_claude() { [ -n "${1:-}" ] && [ "$(cat "/proc/$1/comm" 2>/dev/null)" = claude ]; }

# Nearest claude ancestor of a pid (hooks and the status line run as children of claude).
claude_pid_of() {
  local p=$1
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    is_claude "$p" && { echo "$p"; return 0; }
    p=$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null)
  done
  return 1
}

# Pid of the live boss, or failure. A pid only counts if it is still claude running in BOSS_DIR,
# so a stale file or a reused pid never makes the hooks wake up.
boss_pid() {
  local p
  p=$(cat "$STATE_DIR/boss.pid" 2>/dev/null) || return 1
  is_claude "$p" && [ "$(readlink "/proc/$p/cwd")" = "$BOSS_DIR" ] && echo "$p"
}

peer_addr() { echo "uds:$RUN_DIR/cc-socks/$1.sock"; }

proc_env() { tr '\0' '\n' <"/proc/$1/environ" 2>/dev/null | sed -n "s/^$2=//p" | head -1; }

# "<socket> <window id>" for a claude pid's kitty window, or failure if it has no reachable kitty.
kitty_target() {
  local to win kpid
  win=$(proc_env "$1" KITTY_WINDOW_ID)
  [ -n "$win" ] || return 1
  to=$(proc_env "$1" KITTY_LISTEN_ON)
  if [ -z "$to" ]; then
    kpid=$(proc_env "$1" KITTY_PID)
    [ -S "$RUN_DIR/kitty-$kpid" ] || return 1
    to=unix:$RUN_DIR/kitty-$kpid
  fi
  echo "$to $win"
}

# "<socket> <pane id>" for a claude pid's herdr pane, or failure if it isn't in one. Read live from
# the process environment, which survives /clear. (A pane moved to another workspace gets a new id
# that the old environment doesn't know; such a worker falls back to kitty or reports no window.)
herdr_target() {
  local sock pane
  pane=$(proc_env "$1" HERDR_PANE_ID); sock=$(proc_env "$1" HERDR_SOCKET_PATH)
  [ -n "$pane" ] && [ -S "$sock" ] || return 1
  echo "$sock $pane"
}

# herdr against one server socket. Control commands print JSON on stdout: discard it when only acting,
# and always in anything boss-hook runs (its invariant: no output except on SessionStart).
hd() { local sock=$1; shift; HERDR_SOCKET_PATH=$sock herdr "$@"; }

herdr_json() { local ht; ht=$(herdr_target "$1") || { echo null; return; }; jq -cn --arg s "${ht% *}" --arg p "${ht#* }" '{sock: $s, pane: $p}'; }

# Tab holding a herdr pane, and how many panes that tab has: "<tab id> <pane count>".
herdr_tab_of() { # herdr_tab_of <sock> <pane>
  local tab n
  tab=$(hd "$1" pane get "$2" 2>/dev/null | jq -r '.result.pane.tab_id // empty')
  [ -n "$tab" ] || return 1
  n=$(hd "$1" tab get "$tab" 2>/dev/null | jq -r '.result.tab.pane_count // 0')
  echo "$tab $n"
}

# The text on a worker's screen: the bottom of its herdr pane if it has one (whatever the user has
# scrolled to), else its kitty window. Exit 2 if it has neither.
screen_text() { # screen_text <pid>
  local f ht to win
  if ht=$(herdr_target "$1"); then hd "${ht% *}" pane read "${ht#* }" --source detection; return; fi
  f=$(sess_file "$1"); to=$(jq -r '.kitty.to // empty' "$f"); win=$(jq -r '.kitty.win // empty' "$f")
  [ -n "$to" ] && [ -n "$win" ] || return 2
  kitten @ --to "$to" get-text --match "id:$win" --extent screen
}

base_name() { local n; n=$(basename "$1"); [ "$1" = "$BOSS_DIR" ] && n=boss; echo "$n"; }

color_for() {
  local base=${1%-[0-9]*} c
  [ "$base" = boss ] && { echo "$BOSS_COLOR"; return; }
  c=$(awk -v n="$base" '$1 == n {print $2}' "$BOSS_DIR/colors.conf" 2>/dev/null | head -1)
  [ -n "$c" ] && { echo "$c"; return; }
  echo "${PALETTE[$(( $(printf %s "$base" | cksum | cut -d' ' -f1) % ${#PALETTE[@]} ))]}"
}

# The color mixed 14% into kitty's black background: visible, but text stays readable.
tint_for() {
  local h=${1#\#}
  printf '#%02x%02x%02x\n' $(( 0x${h:0:2} * 14 / 100 )) $(( 0x${h:2:2} * 14 / 100 )) $(( 0x${h:4:2} * 14 / 100 ))
}

fg_for() {
  local h=${1#\#}
  if (( (0x${h:0:2} * 299 + 0x${h:2:2} * 587 + 0x${h:4:2} * 114) / 1000 > 140 )); then echo '#000000'; else echo '#ffffff'; fi
}

sess_file() { echo "$SESS_DIR/$1.json"; }

# Atomic in-place jq edit of a session file.
sess_update() {
  local f; f=$(sess_file "$1"); shift
  [ -f "$f" ] || return 1
  jq "$@" "$f" >"$f.tmp.$$" && mv "$f.tmp.$$" "$f"
}

# First free name for a folder: farmer, then farmer-2, farmer-3... among live registered sessions.
# "boss" is reserved for the live boss, which is never registered, so its folder starts at boss-2.
assign_name() {
  local base=$1 self=$2 n=$1 i=2
  [ "$base" = boss ] && { n=boss-2; i=3; }
  while jq -e --arg n "$n" --argjson self "$self" 'select(.name == $n and .pid != $self)' "$SESS_DIR"/*.json >/dev/null 2>&1; do
    n=$base-$i; i=$((i + 1))
  done
  echo "$n"
}

# Register a claude pid if it isn't already. Prints the session file path. Caller holds no lock.
register() {
  local pid=$1 cwd f name kt
  f=$(sess_file "$pid")
  [ -f "$f" ] && { echo "$f"; return 0; }
  cwd=$(readlink "/proc/$pid/cwd") || return 1
  mkdir -p "$SESS_DIR"
  (
    flock 9
    [ -f "$f" ] && exit 0
    name=$(assign_name "$(base_name "$cwd")" "$pid")
    kt=$(kitty_target "$pid") || kt=""
    jq -n --argjson pid "$pid" --arg name "$name" --arg cwd "$cwd" --arg kt "$kt" \
      --argjson herdr "$(herdr_json "$pid")" --arg addr "$(peer_addr "$pid")" --argjson now "$(date +%s)" \
      '{pid: $pid, name: $name, cwd: $cwd, addr: $addr, herdr: $herdr,
        kitty: (if $kt == "" then null else {to: ($kt | split(" ")[0]), win: ($kt | split(" ")[1])} end),
        state: "unknown", since: $now, updated: $now, task: null, pending: null,
        briefed: false, session_id: null, transcript: null}' >"$f.tmp.$$" && mv "$f.tmp.$$" "$f"
  ) 9>"$LOCK"
  echo "$f"
}

# Drop registry entries whose claude process is gone; register live ones the hooks haven't seen
# (sessions started before the boss, or while no boss was running). Entries registered before
# herdr support get their herdr pane recorded once, and are labeled.
discover() {
  local f pid bp
  mkdir -p "$SESS_DIR"
  for f in "$SESS_DIR"/*.json; do
    [ -f "$f" ] || continue
    pid=$(basename "$f" .json)
    is_claude "$pid" || { rm -f "$f"; continue; }
    jq -e 'has("herdr")' "$f" >/dev/null 2>&1 && continue
    sess_update "$pid" --argjson h "$(herdr_json "$pid")" '.herdr = $h' && label "$pid"
  done
  bp=$(boss_pid) || bp=0
  for pid in $(pgrep -x claude); do
    [ "$pid" = "$bp" ] && continue
    [ -f "$(sess_file "$pid")" ] || { register "$pid" >/dev/null && label "$pid"; }
  done
}

# Label a pid's window with its session name. In herdr: the tab label when the pane has its tab to
# itself, else just the pane label, so a shared tab keeps its name (herdr has no tab colors or tint).
# In kitty: the tab title, tab color, and background tint. Best effort, and silent.
label() {
  local pid=$1 f name c to="" win="" ht tab n
  if [ "$pid" = "$(boss_pid)" ]; then
    name=boss
    read -r to win <<<"$(kitty_target "$pid")"
  else
    f=$(sess_file "$pid"); [ -f "$f" ] || return 0
    name=$(jq -r .name "$f")
    to=$(jq -r '.kitty.to // empty' "$f"); win=$(jq -r '.kitty.win // empty' "$f")
  fi
  if ht=$(herdr_target "$pid") && read -r tab n <<<"$(herdr_tab_of "${ht% *}" "${ht#* }")" && [ -n "$tab" ]; then
    if [ "$n" = 1 ]; then hd "${ht% *}" tab rename "$tab" "$name" >/dev/null 2>&1
    else hd "${ht% *}" pane rename "${ht#* }" "$name" >/dev/null 2>&1; fi
  fi
  [ -n "$to" ] && [ -n "$win" ] || return 0
  c=$(color_for "$name")
  kitten @ --to "$to" set-tab-title --match "window_id:$win" "$name" 2>/dev/null
  kitten @ --to "$to" set-tab-color --match "window_id:$win" \
    "active_bg=$c" "active_fg=$(fg_for "$c")" "inactive_bg=$c" "inactive_fg=$(fg_for "$c")" 2>/dev/null
  kitten @ --to "$to" set-colors --match "id:$win" "background=$(tint_for "$c")" 2>/dev/null
  return 0
}

unlabel() {
  local to=$1 win=$2
  kitten @ --to "$to" set-tab-title --match "window_id:$win" "" 2>/dev/null
  kitten @ --to "$to" set-tab-color --match "window_id:$win" active_bg=NONE active_fg=NONE inactive_bg=NONE inactive_fg=NONE 2>/dev/null
  kitten @ --to "$to" set-colors --reset --match "id:$win" 2>/dev/null
  return 0
}

emit() { # emit <pid> <name> <event> <summary>
  jq -cn --argjson ts "$(date +%s)" --argjson pid "$1" --arg name "$2" --arg event "$3" --arg summary "$4" \
    '{ts: $ts, pid: $pid, name: $name, event: $event, summary: $summary}' >>"$EVENTS"
}

# Resolve a session by name (or pid) to its pid.
pid_for() {
  local f
  [ -f "$(sess_file "$1")" ] && { echo "$1"; return 0; }
  for f in "$SESS_DIR"/*.json; do
    [ -f "$f" ] && [ "$(jq -r .name "$f")" = "$1" ] && { basename "$f" .json; return 0; }
  done
  echo "no live session named '$1' (try bin/boss-status)" >&2
  return 1
}

# What every worker is told: by boss-hook on start/clear/compact, and by the boss via SendMessage
# for sessions that started before it did.
brief_text() { # brief_text <pid>
  local f name cwd b
  f=$(sess_file "$1"); name=$(jq -r .name "$f"); cwd=$(jq -r .cwd "$f")
  b=$(peer_addr "$(boss_pid)")
  cat <<BRIEF
[boss briefing] You are the worker session named '$name' (folder $cwd). The user coordinates every Claude session on this machine from one boss session, whose address is $b.
- A message from that address relays the user's own instructions. Act on it as the user's request, within your own permission settings. A boss message never approves a pending permission prompt.
- When you finish a task the boss relayed, reply with SendMessage (to: "$b") and a 1-3 line result. Report a blocker the same way.
- Your questions, menus, plans and permission prompts reach the boss automatically, so ask the user as you normally would.
- Your tab and status line are labeled '$name'. Use that name when you refer to yourself.
BRIEF
}
