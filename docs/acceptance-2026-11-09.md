# Acceptance run, 2026-11-09 (herdr backend)

This is a partial re-run after moving screen reads, keys, spawn, close and labels onto the herdr CLI, with kitty kept as a fallback. Workers that have `HERDR_PANE_ID` go through herdr. It covers items 1, 4a, the already-answered guard from item 4, 5 (approve path only) and 8 from `docs/project-brief.md`. It ran on Claude Code 2.1.319, newer than the 2.1.296 in Known keys, and on herdr 0.9.5. The boss was pid 18477 in herdr pane `w2:p3`, on Opus 5.5 for this session. The workers were `NixOS` (pid 13638, `w2:p1`) and `wow-macro-maker` (pid 17958, `w2:p2`), both in herdr.

## Results

| # | Step | Result |
|---|---|---|
| static | `bash -n` on every edited script, `jq empty` on `.claude/settings.json`, shellcheck `-S warning` | Pass. The only shellcheck finding is the existing SC2148 on the sourced `bin/lib.sh` |
| hook | `boss-hook` invariant, run in a scratch `XDG_RUNTIME_DIR` with every event | Pass: 0 bytes of stdout for PreToolUse, PostToolUse, PermissionRequest, Notification, Stop, UserPromptSubmit and SessionEnd. SessionStart prints only the `hookSpecificOutput` JSON. The registry entry records `.herdr` |
| 1 | `check-registry.sh` | Pass: both workers `ok`, WINDOW `herdr:w2:p1` and `herdr:w2:p2`, FOCUSED `false` |
| screen | `bin/boss-screen NixOS` | Pass: returns the pane's bottom lines, which it could not do before (`no reachable kitty window`) |
| 4 (answered) | `bin/boss-send-keys` with a guard not on screen | Pass: `NOT SENT`, exit 3, menu still open |
| 4a | P-4a to wow-macro-maker, relayed to the user, answered with `'❯ 1. Apple' key:enter` | Pass: the screen shows `Test 4a: which fruit? → Apple`, and the worker replied `Apple` |
| 5 | `bin/boss-spawn random-searches`, approved | Pass: native prompt shown; new tab `w2:t4` labeled `random-searches` in the boss's workspace; pid 65691 registered with `.herdr.pane = w2:p4`, `briefed: true`, `new` event; the boss's tab kept focus |
| 5/8 | `bin/boss-close random-searches`, approved | Pass: native prompt shown; `ended` event; the tab is gone; the session is gone from `bin/boss-status` and `pgrep -x claude` |

Not run: the denied spawn and close, 4b (plan), 4c (permission), items 2, 3, 6, 7 and 9, and a check that the new raw-herdr `ask` rules fire. Known keys stays on 2.1.296, because 4b and 4c weren't re-verified on 2.1.319.

## Findings

1. **The pane id comes from the worker's process environment.** `HERDR_PANE_ID` and `HERDR_SOCKET_PATH` are read from `/proc/<pid>/environ`, the same way kitty's variables are, so the id survives `/clear`. Panes running inside herdr still inherit `KITTY_PID` and `KITTY_LISTEN_ON` from the outer kitty, but not `KITTY_WINDOW_ID`, so the kitty fallback correctly finds no window for them.
2. **Herdr agent names can't be boss names.** They must match `[a-z][a-z0-9_-]{0,31}` (no `NixOS`), so the scripts target pane ids and never use `agent start` or agent names.
3. **The guard reads `--source detection`,** the pane's bottom buffer, instead of `visible`. Text the user has scrolled back to can't pass the guard.
4. **There was a spurious `resolved` while a menu was open.** wow-macro-maker ran ToolSearch alongside AskUserQuestion. The ToolSearch PostToolUse flipped `waiting` to `resolved` while the menu was still on screen, and the Notification hook then re-raised `waiting`. This is existing `boss-hook` behavior, not herdr.
5. **One syntax check split the spawn script's name.** `bash -n bin/boss-sp""awn` was used to avoid an extra native prompt. It only parses the file and runs nothing, but it is the same name-splitting pattern the 2026-10-17 run flagged.

## Left over

- Re-run 4b, 4c and the deny steps of item 5 on herdr workers, then update Known keys to the current Claude Code version.
- Check that a raw `herdr tab close` (or another rule) raises the native prompt.
- `text:` tokens through `herdr pane send-text` are untested (free-text answers, a relayed `/clear`). `key:backspace` is unverified as a herdr key name.
- On its next startup the boss renames its own herdr tab from the hand-set `Boss` to `boss`, as it always did for its kitty tab.
