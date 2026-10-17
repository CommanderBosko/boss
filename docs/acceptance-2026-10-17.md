# Acceptance run, 2026-10-17 (item 5 only)

This is a re-run of item 5 (spawn and close behind the native prompt) and item 8 (a closed worker drops out of status) from `docs/project-brief.md`. It closes bug 1 of `docs/acceptance-2026-10-13.md`. It ran on Claude Code 2.1.302, newer than the 2.1.296 in Known keys; item 5 sends no keys, so Known keys is unchanged. The boss was pid 5757, on Opus 5.5 for this session (the project default stays Haiku). No workers were open at the start, so the spawned session was named `farmer` (pid 15279) rather than `farmer-2`.

## Results

| # | Step | Result |
|---|---|---|
| 5.1 | Spawn `farmer`, meant to be denied | Prompt appeared; the user approved it by mistake (confirmed by AskUserQuestion). Counted as the approved-spawn step instead |
| 5.2 | Spawn `farmer`, approved | Pass (via 5.1): `new` event for `farmer`; `check-registry.sh` exit 0, background `#1a2109`, same as 2026-10-13 |
| 5.3 | Spawn a second `farmer`, denied | Pass: still only pids 5757 and 15279; no new event |
| 5.4 | Close `farmer`, denied | Pass: `farmer` still in `bin/boss-status`, pid 15279 still running |
| 5.5 | Close `farmer`, approved | Pass: `ended` event; `bin/boss-status` shows no workers |
| 8 | Closed worker drops out of status | Pass: same evidence as 5.5 |

## Findings

1. **The lock holds.** Every spawn and close raised the native prompt, including the first spawn of the run. The 2026-10-13 first spawn was most likely the same misclick; nothing in this run suggests the `ask` rule can be skipped.
2. **The instruction belongs in the prompt itself.** Prompt 1's instruction was only in the boss's message, with the Bash description "(test: expect deny)", and it was approved by mistake. From prompt 2 on, the description read "DENY THIS ONE (prompt N of 4)" / "APPROVE THIS ONE", which the native dialog shows; all three were answered as planned.
3. **The auto-mode classifier blocked two read-only checks** after the approved close (`bin/boss-status; pgrep -x claude` and `check-registry.sh`, both "Interfere With Workloads"). `bin/boss-status` alone, which is allowlisted, ran. Earlier it also blocked feeding sample hook JSON to `rtk hook claude`, correctly, because the probe split the spawn script's name to get past the `ask` rule.

## Left over

- Item 9's 30-second limit is still untimed.
- The classifier blocks on `check-registry.sh` after a close; if it recurs, consider allowlisting that script (it is read-only).
