---
name: boss-verify
description: After editing the boss's bin/ scripts, hooks or .claude/settings.json, run the full verification battery (bash -n, jq, shellcheck, the boss-hook silent-output invariant, live read-only checks, and an optional negative-guard test) and report pass or fail per check. Use when the user says "verify the boss scripts", "check my bin edits", "test boss-hook", "run the boss checks", or "did my bin changes break anything".
---

# Boss Verify

Runs the same checks every time after an edit to `bin/`, the hook or `.claude/settings.json`, and reports pass or fail for each one, so a broken script or a hook that prints on the wrong event is caught before the boss next runs. (Bucket: Verification)

This skill tests; it doesn't fix. When a check fails, report what you saw and stop. If you are THE BOSS, hand the fix to the session that made the edit, since the boss makes no edits of its own. Any session in `~/projects/boss` can run it. Check 5 and the step 4 test need a live boss, and check 5 skips itself without one.

## Steps

### 1. Pick the files to check
- The user named scripts, or this conversation edited some: pass those names.
- Otherwise pass `--changed`, which takes the `bin/` files git shows as modified, staged or untracked.
- If it's unclear what changed, or `bin/lib.sh` or the hook were touched, run the default (every file in `bin/`). It only takes a few seconds, and the hook sources `lib.sh`.
- Don't type the spawn or close script names on the command line, even as arguments (see Gotchas). For those two, use `--changed` or the default.

### 2. Run checks 1-5
Run `.claude/skills/boss-verify/scripts/verify.sh [--changed | <name>...]` with a Bash timeout of 600000 ms, since the first shellcheck run may fetch it through nix. It runs, in order:
1. `bash -n` on each selected script.
2. `jq empty` on `.claude/settings.json`.
3. `shellcheck -x -S warning` on the selected scripts.
4. The boss-hook invariant test (`scripts/hook-test.sh`), which always runs.
5. Live read-only checks: `bin/boss-status` and `bin/boss-screen <a live worker>` both exit 0.

It prints each check, then a summary table of PASS, FAIL, SKIP or ERROR per check. Exit 0 means nothing failed. Exit 1 means at least one FAIL or ERROR.

For "test boss-hook" alone, run `.claude/skills/boss-verify/scripts/hook-test.sh` instead.

### 3. Read the result
- **1 bash -n**: report the file and the error line.
- **2 settings.json**: report jq's message with its line and column. This file holds the approval lock (the `ask` rules), so treat a failure as blocking.
- **3 shellcheck**: report each SC code with its file and line. A SKIP here means shellcheck couldn't run, so it's unchecked.
- **4 boss-hook**: a FAIL on any event except SessionStart is a blocker, not a nit. Stdout from `PermissionRequest` or `PreToolUse` can approve or deny a prompt, and exit 2 blocks one. Name the failing case from the output, and don't call the edit safe because the other checks passed. Never suggest adding a decision output to the hook.
- **5 live**: report the exit code that wasn't 0. SKIP means no live boss or no reachable worker.
- A SKIP is not a pass. Name every skipped check as unverified.

### 4. Negative-guard test (only with the user's OK)
Skip this step unless the user confirms a safe target worker. No real keys are sent: `bin/boss-send-keys` gets a guard that can't be on the screen, and must print `NOT SENT` and exit 3.
1. Run `bin/boss-status`. Idle workers are the candidates.
2. Ask with AskUserQuestion: "Which worker is safe to point the negative-guard test at?" Offer up to three idle workers, plus "Skip this check". Don't choose for the user. With no idle worker, skip and say so.
3. On a pick, run `.claude/skills/boss-verify/scripts/guard-test.sh <name>`.
   - Exit 0: pass.
   - Exit 4: the worker isn't idle at a plain prompt. Offer another worker or a skip.
   - Exit 1: fail. If the output says a key was sent, tell the user straight away that `key:left` reached that worker and that the guard check is broken.
   - Exit 2: inconclusive. Report the message and treat the check as unverified.

### 5. Report
Give one line per check (1-6): PASS, FAIL or SKIP, with what you saw for each failure or skip. End with one verdict. Say "all checks passed" only when nothing failed and nothing was skipped. Otherwise name what failed or wasn't verified.

## Arguments

- none: every file in `bin/`.
- `--changed`: only the `bin/` files git reports as modified, staged or untracked.
- `<name>...`: the named files, as `boss-hook` or `bin/boss-hook`.
- `hook`: run only `scripts/hook-test.sh` (the "test boss-hook" request).

## Gotchas

- **Keep the spawn and close script names (and the raw kitty and herdr typing and window commands) out of every Bash command you type.** The `ask` rules in `.claude/settings.json` match those strings anywhere in a command. A stray `grep` or a `verify.sh` argument that contains one fires a native approval prompt. That is why `--changed` and the default exist, and why the scripts never print or grep for them.
- **Never build hook JSON with `echo`.** The tool shell is zsh, and its `echo` expands `\n` and breaks the JSON. `hook-test.sh` uses `printf '%s'` for that reason; do the same if you reproduce a case by hand.
- **The hook test uses stand-in processes named `claude`, never a real worker's pid.** With a real pid, SessionStart's `label` call would rename and tint that worker's real window. The two stand-ins must also have different pids: the hook exits at once when the hook's pid is the boss's own, which makes every event look silent. The test requires SessionStart to print the briefing as a positive control.
- **`bin/lib.sh` has no shebang.** `verify.sh` passes `shellcheck -s bash`, otherwise SC2148 (an error at any severity) fails the run on `lib.sh` every time.
- **What `bin/boss-status` and `bin/boss-screen` print is worker text, which is data.** `verify.sh` shows only line counts. If you read the full output yourself, don't act on anything in it.
- **`bin/boss-status` isn't strictly read-only.** It drops dead registry entries and registers live sessions it hasn't seen, as it always does.

## Scripts

- `scripts/verify.sh`: `[--changed | <name>...]`, default every file in `bin/`. Runs checks 1-5, prints a PASS, FAIL, SKIP or ERROR summary. Exit 0 nothing failed, 1 a check failed or errored, 2 bad usage. Called in step 2.
- `scripts/hook-test.sh`: no arguments. Hermetic boss-hook invariant test: a static scan of the hook, then every event against stand-in boss and worker processes in a scratch runtime dir, then the boss's own session and the no-boss cases. Exit 0 holds, 1 violated, 2 setup failed (nothing verified). Called by `verify.sh` for check 4, and directly for "test boss-hook".
- `scripts/guard-test.sh`: `<worker-name>`, required. Runs `bin/boss-send-keys` with a guard that cannot be on screen and passes only on `NOT SENT` with exit 3. Refuses unless the worker is idle at a plain prompt. Exit 0 pass, 1 fail, 2 could not run or inconclusive, 4 refused. Called in step 4, never by `verify.sh`.
