# boss

A coordinator for running many Claude Code sessions at once. Any `claude` opened in this folder becomes **the boss**: one terminal that tracks every other local Claude session, relays your instructions and their replies, and brings you every question, plan or permission prompt a worker is blocked on, then answers it with your choice. Each worker's kitty window gets a stable per-folder name and color, so you can tell windows apart at a glance.

## Current Status

Everything in the definition of done (`docs/project-brief.md`) is live. The 2026-10-13 acceptance run re-verified it, with item 5 marked partial: one spawn prompt went unrecorded. The band above the boss's prompt now loads as a project-scoped plugin. See `project-state.md` for what's pending and `session-summary.md` for the session log.

## What it does

- **Status**: one line per live `claude` process, showing its name, folder, and whether it is working, idle or waiting on you.
- **The band**: a live row per worker above the boss's prompt, showing its color, state, time in that state, and task.
- **Two-way relay**: `<name>: <instruction>` goes to that session over Claude Code's peer messaging (SendMessage), and its reply comes back to the boss.
- **Blocked-worker relay**: AskUserQuestion menus, plan approvals and permission prompts are shown in the boss with their exact text and options. The boss re-reads the worker's screen and presses the keys you chose, and it sends nothing if the prompt is already gone.
- **Labels**: kitty tab title, tab color, a subtle background tint, and a colored status line for every session.
- **Spawn and close**: opens or closes worker windows only after Claude Code's own permission prompt gets your yes. Several sessions can go in one call, behind one prompt.
- **Briefing**: workers learn their name and how to report back on start, after `/clear`, and after compaction.

The boss never does project work and never auto-approves anything. See `docs/project-brief.md` for the full scope and `docs/acceptance-*.md` for the acceptance runs.

## Tech Stack

- Bash scripts in `bin/`, with shared helpers in `bin/lib.sh`
- [jq](https://jqlang.org/) for the session registry and event log
- [kitty](https://sw.kovidgoyal.net/kitty/) remote control (`kitten @`) for labels, screen reads and keypresses
- Claude Code hooks, peer messaging (ListAgents/SendMessage) and the Monitor tool
- A Claude Code plugin (TypeScript/TSX) for the band, in `mods/boss-band/`
- Linux `/proc` for discovering `claude` processes

## Setup

1. Clone to `~/projects/boss`. `bin/boss-spawn` resolves bare folder names under `~/projects` and `~`.
2. Give kitty remote control: `allow_remote_control socket-only` and `listen_on unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}`. An always-on tab bar (`tab_bar_min_tabs 1`) shows the labels.
3. Wire `bin/boss-hook` as a global hook, so it runs in *every* Claude session, for `SessionStart`, `UserPromptSubmit`, `PreToolUse` (matcher `AskUserQuestion|ExitPlanMode`), `PermissionRequest`, `Notification`, `PostToolUse`, `Stop` and `SessionEnd`. It stays inert unless a live boss is running.
4. Optionally, set `bin/boss-statusline` as the Claude Code status line.
5. Copy `projects.local.md.example` to `projects.local.md` and `colors.conf.example` to `colors.conf`, then fill in your own projects and colors. Both copies are gitignored.

`.claude/settings.json` in this folder wires `bin/boss-init` as the SessionStart hook and carries the approval lock: `ask` rules on `boss-spawn`, `boss-close` and raw `kitten @` send/launch/close commands. It also registers this repo as a folder plugin marketplace (`.claude-plugin/marketplace.json`) and enables the `boss-band` plugin at project scope, so the band loads only in sessions started here. After editing `mods/boss-band/`, run `/reload-plugins`.

## Usage

Open `claude` in this folder. `bin/boss-init` claims the boss role. A second `claude` opened here while a boss is alive works as a normal session. Then talk to the boss:

```text
status
farmer: run the tests and tell me what fails
start a session in screeps
```

State lives in `$XDG_RUNTIME_DIR/claude-boss/`: `boss.pid`, the `sessions/<pid>.json` registry, and the `events.jsonl` log that `bin/boss-watch` streams to the boss.

## Project Structure

- `bin/`: the boss scripts (`boss-hook`, `boss-init`, `boss-watch`, `boss-spawn`, `boss-close`, `boss-send-keys`, …) and the shared `lib.sh`
- `mods/boss-band/`: the band plugin
- `.claude/skills/`: `boss-acceptance` (re-runs the definition of done) and `secret-scan` (pre-push check)
- `docs/`: the project brief and the dated acceptance runs
- `CLAUDE.md`: the boss's operating rules, including the verified key mappings for each prompt type

## Recent Changes

- **2026-10-13**: spawn and close take several names behind one prompt. The band became a project-scoped plugin, so restarts no longer drop it. Added the `boss-acceptance` skill and recorded a second acceptance run. Read-only boss scripts no longer prompt. Added a `secret-scan` skill.

## License

MIT
