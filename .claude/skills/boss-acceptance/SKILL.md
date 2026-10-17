---
name: boss-acceptance
description: Re-run the boss's definition of done (docs/project-brief.md) against live workers with fixed worker prompts, relay each prompt through the normal waiting flow, and write a dated docs/acceptance-<date>.md. Use when the user says "run the acceptance test", "re-verify the boss", "boss-acceptance", "check the known keys still work", or "regression-test the boss".
---

# Boss Acceptance

Re-runs the nine definition-of-done items in `docs/project-brief.md` against live workers and records the results, so a Claude Code upgrade or a change to `bin/` gets verified the same way every time. (Bucket: Verification)

Only THE BOSS runs this. If `[boss-init]` said another boss is running, stop and say so. This skill tests; it doesn't fix. When an item fails, record what you saw and keep going. Fixing it is separate work for after the report. The one edit outside `docs/` is step 10's update to CLAUDE.md's **Known keys**, which records what the run verified; it never changes how anything behaves.

## Steps

### 1. Preflight
- Make sure the `/home/bosko/projects/boss/bin/boss-watch` Monitor is armed (absolute path, as in CLAUDE.md), and re-arm it if it has expired.
- Run `bin/boss-status`, then `.claude/skills/boss-acceptance/scripts/preflight.sh`. Exit 1 means fewer than two kitty workers, or none in a git repo (e.g. you want `NixOS` and `farmer`): stop and ask the user to open them. Don't spawn them yourself: spawning is item 5's test. Exit 3 means `claude --version` differs from the **Known keys** version in `CLAUDE.md`, so every key mapping counts as unverified until items 4a–4c pass.
- Tell the user which workers the run uses. Don't list the native prompts coming in item 5 (see Gotchas).

Worker prompts come from `assets/worker-prompts.md`. Send each one word for word with SendMessage to the worker's address. Note the time of each send, since several items have a 30-second limit.

### 2. Item 1: status matches the processes
Run `bin/boss-status`, then `.claude/skills/boss-acceptance/scripts/check-registry.sh`. Exit 0 is a pass. Exit 1 marks each mismatched pid in the CHECK column; record it.

### 3. Item 2: labels
Ask the user with AskUserQuestion (Pass / Fail) whether a screenshot shows every worker with a distinct tab name, tint and status line. Keep the BACKGROUND column from step 2: item 5's new `farmer-2` must show the same background as `farmer`.

### 4. Item 3: relay without focus
Send **P-3** to the git-repo worker. Pass if its reply reaches the boss and `check-registry.sh` shows FOCUSED `false` for that worker both before and after.

### 5. Item 4: blocked-worker relay
Run these one at a time. For each, send the prompt, then wait for the `waiting` event, which must come within 30 s. Then follow CLAUDE.md's `waiting` flow exactly: `bin/boss-pending`, AskUserQuestion, `bin/boss-screen`, `bin/boss-send-keys` with a live-only guard, then check the screen it prints.

Take each guard from CLAUDE.md's **Known keys**, the source of truth, so this table can't drift from it:

| Item | Prompt | Guard (Known keys entry) |
|---|---|---|
| 4a menu | P-4a | AskUserQuestion menus: the cursor line for P-4a's first option |
| 4b plan | P-4b | Plan approvals |
| 4c permission | P-4c | Permission prompts, `ask`-rule variant |

Pass when the worker's reply matches what the user picked. Judge whether a prompt appeared from the `waiting` event and the screen, never from the worker's own account.

**Already answered.** Send **P-4d** to the other worker. When its `waiting` event arrives, ask the user to answer it in that worker's own window and tell you when it's done. Then run `bin/boss-send-keys <name> '❯ 1. Red' key:enter`. Pass is `NOT SENT` with exit 3.

### 6. Item 5 and item 8: spawn and close
There are four native prompts, strictly one per message. Right before each, give one bold line, e.g. **Prompt 1 of 4, spawning `farmer`: DENY this one.** Put the same instruction in the Bash call's `description`, e.g. `DENY THIS ONE (prompt 1 of 4): spawn farmer`, since the native dialog shows the description. Before each deny, also tell the user to type "continue" afterwards.
1. `bin/boss-spawn farmer`, denied. Pass: no new pid in `pgrep -x claude`, and no `new` event.
2. `bin/boss-spawn farmer`, approved. Pass: a `new` event for `farmer-2`, and `check-registry.sh` passes with `farmer-2` on farmer's background.
3. `bin/boss-close farmer-2`, denied. Pass: it's still in `bin/boss-status`.
4. `bin/boss-close farmer-2`, approved. Pass: an `ended` event, and `farmer-2` is gone from `bin/boss-status` (item 8).

### 7. Item 6: re-brief after /clear and /compact
Ask the user to run `/clear` in one worker's window. Pass: a `clear` event within 30 s, then **P-name** gets back the right name. Repeat with `/compact`, which needs a `compact` event.

### 8. Item 7: no stray boss role
Send **P-role** to a worker outside `~/projects/boss` and expect `NO-BOSS-ROLE`. Then ask the user to open a second `claude` in `~/projects/boss` and ask it "who are you?". Pass: a `new` event for `boss-2`, and it doesn't claim the boss role. Ask the user to close that window themselves.

### 9. Item 9: quiet while busy
Send **P-busy**. Pass: you post nothing until the `finished` event, and that arrives within 30 s of the worker finishing.

### 10. Write the record
Write `docs/acceptance-<YYYY-MM-DD>.md`, or `-2` and so on if that file exists. Follow the layout of `docs/acceptance-2026-10-12.md`: a header with the Claude Code version and worker pids, a Results table with one row per item, then "Bugs found" and "Left over". If items 4a–4c passed on a newer Claude Code version, update the version on CLAUDE.md's **Known keys** line, plus any key or guard that changed.

Last, ask the user to run `/clear` in the boss, then `/boss-acceptance post-clear`.

### 11. Report
Give one line per item (pass or fail), the doc path, and what you saw for each failure.

## Arguments

- `post-clear`: after the boss's own `/clear`, run only steps 1, 2 and 5, then add an "After the boss's `/clear`" section to today's doc.

## Gotchas

- **Never list the approve/deny sequence up front.** On 2026-10-12 a five-step list made the user approve spawns meant to be denied, and the test had to restart. Give one instruction right before each prompt, and check the result before announcing the next.
- **A denied prompt ends the boss's turn.** Before every planned deny, tell the user to type "continue".
- **If `resolved` arrives before you send keys, that relay didn't pass.** The user answered in the worker's window (4b's first try, 2026-10-12). Re-send the prompt with a new tag, e.g. `PLAN-OK-2`.
- **Keep the spawn and close script names out of every other Bash command.** The `ask` rules match them anywhere, so a stray `grep` fires an extra native prompt and throws off the count.
- **After the boss's `/clear`, `bin/boss-watch` exits at once with no output.** That's expected: the watcher from before the clear still holds the lock. Re-arm it when it expires.

## Scripts

- `scripts/preflight.sh`: read-only, no arguments. Prints the kitty worker count, which workers are in a git repo, and `claude --version` against the Known keys version. Exit 0 ready, 1 not enough workers, 2 no live boss, 3 ready but the version changed. Called in step 1.
- `scripts/check-registry.sh`: read-only, no arguments. Prints PID, NAME, FOLDER, BACKGROUND, FOCUSED and CHECK for every worker. Exit 0 if the registry matches `pgrep -x claude` minus the boss, 1 on a mismatch, 2 if no boss is live. Called in steps 2, 4 and 6.

## Assets

- `assets/worker-prompts.md`: the canonical worker prompts (P-3, P-4a to P-4d, P-name, P-role, P-busy). Read it in step 1.
