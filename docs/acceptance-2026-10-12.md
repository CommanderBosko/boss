# Acceptance run, 2026-10-12

This is a run of the definition of done in `docs/project-brief.md`, made after the NixOS rebuild with Claude Code 2.1.296. The workers were `farmer` (pid 36417) and `NixOS` (pid 37072).

## Results

| # | Item | Result |
|---|---|---|
| 1 | `status` matches `pgrep -x claude`, minus the boss | Pass: names and folders match `/proc` |
| 2 | Each worker identifiable in one screenshot; same color after restart | Pass: tab, tint and status line are red for NixOS and green for farmer. farmer was `#1a2109` before and after a restart |
| 3 | `NixOS: run git status…` answered in the boss, window never focused | Pass: `is_focused` stayed false |
| 4a | AskUserQuestion menu relayed and answered | Pass |
| 4b | Plan approval relayed and answered | Pass (on the second try; on the first, the user approved it in the worker window) |
| 4c | `chmod -R` permission prompt relayed and answered | Pass |
| 4 | A prompt already answered in the worker means nothing is sent | Pass: `NOT SENT`, exit 3, when guarded on the live cursor line |
| 5 | Spawn deny / approve, close deny / approve | Pass, all four |
| 6 | Re-brief after `/clear` and after `/compact`; worker states its name | Pass, after fix 3 below |
| 7 | farmer loads no boss role; a second claude in `~/projects/boss` isn't the boss | Pass, after fix 4 below |
| 8 | Closing a worker drops it from `status` | Pass |
| 8 | After the boss's own `/clear`, items 1 and 4 still pass | Pass: see "After the boss's `/clear`" below |
| 9 | Silent while a worker is busy; `finished` within 30 s | Pass |

## Bugs found and fixed during the run

1. **Fresh starts logged as `startup`, so the watcher dropped them.** `boss-spawn` registers the pid before SessionStart fires. Fixed in `boss-hook`: `source: startup` always counts as `new`.
2. **The task summary was the raw `<cross-session-message …>` wrapper.** Fixed in `boss-hook`: the wrapper is stripped before the 120-character cut.
3. **`/clear` showed up as `ended` and then `new`, not as `clear`.** SessionEnd fires with `reason: clear` and was deleting the registry entry and the label. Fixed in `boss-hook`: SessionEnd with reason `clear` is now a no-op.
4. **A second claude in the boss folder was named `boss`**, and got the boss's label. Fixed in `lib.sh` `assign_name`: `boss` is reserved, so the next one is `boss-2`.
5. **A close logged `ended` twice**, once from the hook and once from `boss-close`. Fixed: `boss-close` logs only if the hook didn't run.
6. **The boss asked the user about a plan that had already been answered**, because `boss-watch` filtered out `resolved`. Fixed: the watcher passes `resolved`, and CLAUDE.md says what to do with it.
7. **The send-keys guard was weak.** The question and plan text stay on screen after an answer, so a guard on them still matches. Fixed in the CLAUDE.md guidance and the `boss-send-keys` usage text: guard on text only the live prompt shows. The verified guards and keys for plans and permissions are now under Known keys.

## After the boss's `/clear`

The boss (pid 32014) ran `/clear`. `boss-init` re-claimed the role with source `clear`.

- **Watcher.** The new `boss-watch` exited at once because the pre-`/clear` watcher, a child of the same claude pid, still held the lock. Every event below came in through that old Monitor, so a `/clear` doesn't drop the watch. It still expires 30 minutes after its own start, and the boss re-arms it then.
- **Item 1.** Pass. The registry lists `36417` farmer and `37072` NixOS. `pgrep -x claude` lists those two plus the boss.
- **Item 4a, menu.** Pass. farmer's "Which fruit?" was relayed and Banana was picked with `key:down key:enter`, guarded on `❯ 1. Apple`. farmer replied "Banana".
- **Item 4b, plan.** Pass. NixOS's no-op plan was relayed and approved with option 1, `key:enter`, guarded on `Would you like to proceed?`. NixOS replied "plan approved".
- **Item 4c, permission.** Pass. farmer's `chmod -R u+rw /tmp/boss-accept-chmod` hit the managed `Bash(chmod -R *)` rule. It was approved with `key:enter`, guarded on `requires confirmation for this command.`, and farmer replied "chmod ran". farmer also said no prompt had appeared. That was wrong, since the screen and the `waiting: permission` event both show the prompt. A worker can't see a prompt that was answered for it, so a worker's word on whether it was prompted isn't evidence.
- **Already answered.** Pass. The user answered NixOS's "Which color?" in its own window, picking Blue. The boss's `boss-send-keys NixOS '❯ 1. Red' …` then returned `NOT SENT`, exit 3.

## Left over

- Not required by the brief: the niri window titles still read `✳ Claude Code`, not the session name.
