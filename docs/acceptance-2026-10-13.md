# Acceptance run, 2026-10-13

This is a run of the definition of done in `docs/project-brief.md`, made with Claude Code 2.1.296. The boss was pid 1037357. The workers were `farmer` (pid 1038712) and `NixOS` (pid 1038186). `farmer-2` (pids 1045354, then 1050361) was used for item 5 and closed both times. `boss-2` (a second claude in `~/projects/boss`, pid not recorded) was used for item 7. The user was asked to close it.

## Results

| # | Item | Result |
|---|---|---|
| 1 | `status` matches `pgrep -x claude`, minus the boss | Pass: `check-registry.sh` exit 0 with farmer and NixOS |
| 2 | Each worker identifiable in one screenshot | Pass: user confirmed from a screenshot. NixOS `#20030a`, farmer `#1a2109`, same before and after `farmer-2` |
| 3 | Git-repo worker answers the boss, window never focused | Pass: farmer replied "on branch main, clean"; `FOCUSED false` before and after |
| 4a | AskUserQuestion menu relayed and answered | Pass: user picked Banana; farmer replied "Banana" |
| 4b | Plan approval relayed and answered | Pass: user approved; farmer replied PLAN-OK |
| 4c | `chmod -R` permission prompt relayed and answered | Pass: user approved; farmer replied CHMOD-RAN |
| 4d | Prompt already answered in the worker means nothing is sent | Pass: user answered NixOS in its window (Blue); `NOT SENT`, exit 3 |
| 5 | Spawn deny / approve, close deny / approve | Partial: see "Bugs found" 1. Final sequence: denied spawn left no session; approved spawn created `farmer-2`; denied close left it open; approved close ended it |
| 6 | Re-brief after `/clear` and after `/compact`; worker states its name | Pass: `clear` event, then "farmer"; `compact` event, then "farmer post-compact" |
| 7 | farmer loads no boss role; a second claude in `~/projects/boss` isn't the boss | Pass: farmer replied NO-BOSS-ROLE; `boss-2` answered "I'm … the worker session boss-2 … not the coordinator here" |
| 8 | Closing a worker drops it from `status` | Pass: `farmer-2` gone from `bin/boss-status` after the approved close |
| 9 | Silent while a worker is busy; `finished` within 30 s | Pass: nothing posted until NixOS's BUSY-DONE and `finished`. The 30 s limit was not timed |

Not run: "After the boss's `/clear`". The user has not asked for that section yet.

## Bugs found

1. **Item 5 went off-script at the first spawn.** The first `bin/boss-spawn farmer` ran with no deny, opening `farmer-2`, and the approved close ended it. Nothing in this run shows whether a native prompt appeared for that spawn. The user later confirmed that spawn and close prompts do appear in this window, and both later prompts appeared and were denied or approved as planned. So the lock works. The first spawn's prompt is unaccounted for.
2. **Identical messages to a worker were dropped as duplicates.** Farmer's first reply ("farmer") to the post-`/compact` check was dropped, as was the boss's identical repeat request. The fix was a reworded request ("…followed by the word post-compact"). Repeating the same text to a session is not reliable.
3. **The HUD band is missing entirely.** `bin/boss-rows` returns the workers correctly, and the status line shows `boss · 2 workers`. The band is the `boss-band` dev mod (`~/.claude/dev-mods/96a9575b…/boss-band`). It hides when the poll returns null or no rows. No log of the mod exists on disk. The likely cause is that the mod's `session.start` didn't run in this boss session. Not fixed in this run.

## Left over

- The HUD band (bug 3): decide whether to restart the boss window to re-run `session.start`, or investigate the mod's host.
- Item 5's first spawn (bug 1): if it matters, rerun the denied-spawn step with the boss watching the prompt.
- Item 9's 30-second limit was not timed; a rerun with a timestamp would close it.
- `boss-2` was started for item 7 and must be closed; the user closes it.
- Not required by the brief: the niri window titles still read `✳ Claude Code`, not the session name.
