# boss

A coordinator for running many Claude Code sessions at once. Any `claude` opened in this folder becomes **the boss**: one terminal that tracks every other local Claude session, relays your instructions and their replies, and brings you every question, plan or permission prompt a worker is blocked on, then answers it with your choice. Each worker's kitty window gets a stable per-folder name and color, so you can tell windows apart at a glance.

## What it does

- **Status**: one line per live `claude` process, showing its name, folder, and whether it is working, idle or waiting on you.
- **Two-way relay**: `<name>: <instruction>` goes to that session over Claude Code's peer messaging (SendMessage), and its reply comes back to the boss.
- **Blocked-worker relay**: AskUserQuestion menus, plan approvals and permission prompts are shown in the boss with their exact text and options. The boss re-reads the worker's screen and presses the keys you chose, and it sends nothing if the prompt is already gone.
- **Labels**: kitty tab title, tab color, a subtle background tint, and a colored status line for every session.
- **Spawn and close**: opens or closes worker windows only after Claude Code's own permission prompt gets your yes.
- **Briefing**: workers learn their name and how to report back on start, after `/clear`, and after compaction.

The boss never does project work and never auto-approves anything. See `docs/project-brief.md` for the full scope and `docs/acceptance-2026-10-12.md` for the acceptance run.

## Tech Stack

- Bash scripts in `bin/`, with shared helpers in `bin/lib.sh`
- [jq](https://jqlang.org/) for the session registry and event log
- [kitty](https://sw.kovidgoyal.net/kitty/) remote control (`kitten @`) for labels, screen reads and keypresses
- Claude Code hooks, peer messaging (ListAgents/SendMessage) and the Monitor tool
- Linux `/proc` for discovering `claude` processes

## Setup

1. Clone to `~/projects/boss`. `bin/boss-spawn` resolves bare folder names under `~/projects` and `~`.
2. Give kitty remote control: `allow_remote_control socket-only` and `listen_on unix:${XDG_RUNTIME_DIR}/kitty-{kitty_pid}`. An always-on tab bar (`tab_bar_min_tabs 1`) shows the labels.
3. Wire `bin/boss-hook` as a global hook, so it runs in *every* Claude session, for `SessionStart`, `UserPromptSubmit`, `PreToolUse` (matcher `AskUserQuestion|ExitPlanMode`), `PermissionRequest`, `Notification`, `PostToolUse`, `Stop` and `SessionEnd`. It stays inert unless a live boss is running.
4. Optionally, set `bin/boss-statusline` as the Claude Code status line.
5. Copy `projects.local.md.example` to `projects.local.md` and `colors.conf.example` to `colors.conf`, then fill in your own projects and colors. Both copies are gitignored.

`.claude/settings.json` in this folder wires `bin/boss-init` as the SessionStart hook and carries the approval lock: `ask` rules on `boss-spawn`, `boss-close` and raw `kitten @` send/launch/close commands.

## Usage

Open `claude` in this folder. `bin/boss-init` claims the boss role. A second `claude` opened here while a boss is alive works as a normal session. Then talk to the boss:

```text
status
farmer: run the tests and tell me what fails
start a session in screeps
```

State lives in `$XDG_RUNTIME_DIR/claude-boss/`: `boss.pid`, the `sessions/<pid>.json` registry, and the `events.jsonl` log that `bin/boss-watch` streams to the boss.

## License

MIT
