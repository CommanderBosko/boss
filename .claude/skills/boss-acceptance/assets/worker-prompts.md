# Canonical worker prompts

Send each one word for word with SendMessage to the worker's address (from `bin/boss-status` / the registry). Change only a `<placeholder>`, or a tag suffix on a re-run (`PLAN-OK-2`). These are the wordings that worked in the 2026-10-12 run.

**P-3** (item 3, to a worker in a git repo):
> From the user: run git status and tell me the branch.

**P-4a** (item 4a, menu):
> From the boss (acceptance test, no project work): please call AskUserQuestion once with the question "Test 4a: which fruit?" and the options "Apple" and "Banana". Then reply to me with the option the user picked, and nothing else.

**P-4b** (item 4b, plan):
> From the boss (acceptance test, no project work): please enter plan mode and submit this plan for approval with ExitPlanMode, without reading or changing any files. Plan: "Test 4b: reply to the boss with the word PLAN-OK. No other actions." If the plan is approved, do exactly that. If it's rejected, reply PLAN-REJECTED.

**P-4c** (item 4c, permission from the managed `ask` list):
> From the boss (acceptance test, no project work): Test 4c. First run `mkdir -p /tmp/boss-test-4c` on its own. Then run exactly `chmod -R u+rw /tmp/boss-test-4c` as a separate Bash call. It should hit a permission prompt, so wait for it to be answered. Reply to me with CHMOD-RAN if it ran, or CHMOD-DENIED if it was denied.

**P-4d** (item 4, already answered in the worker's window):
> From the boss (acceptance test, no project work): please call AskUserQuestion once with the question "Test 4d: which color?" and the options "Red" and "Blue". Then reply to me with the option the user picked, and nothing else.

**P-name** (items 6 and 7):
> From the boss (acceptance test, no project work): reply with just your session name as your boss briefing gives it.

**P-role** (item 7, to a worker outside `~/projects/boss`):
> From the boss (acceptance test, no project work): without reading any files, answer from your loaded instructions alone: were you told you are THE BOSS, or given a "Boss role" section? Reply BOSS-ROLE or NO-BOSS-ROLE, and nothing else.

**P-busy** (item 9):
> From the boss (acceptance test, no project work): run exactly `timeout 45 tail -f /dev/null; true` as one Bash call, then reply to me with BUSY-DONE.
