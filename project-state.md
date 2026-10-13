# Project State

The scope is `docs/project-brief.md`, and its definition of done is the acceptance test. `CLAUDE.md` is the source of truth for how the boss behaves and for the verified **Known keys**. This file tracks what is live, what is pending and why.

## Current Project State

**2026-10-13: batching, the band as a plugin, a re-runnable acceptance test, improve-system fixes, secret scan**
- **Live and verified:** everything the 2026-10-12 rebuild shipped (registry, hooks, relay, blocked-worker relay, labels, spawn/close behind the native prompt), re-verified by the 2026-10-13 acceptance run (`docs/acceptance-2026-10-13.md`). Every item passed except item 5, which is marked partial (see Known Issues).
- **Batch spawn/close:** `bin/boss-spawn` and `bin/boss-close` take several names behind one native prompt, keep going past a failed item, and exit 1 if any failed. Verified with five spawns and three closes, one prompt each.
- **The band** (worker rows above the boss's prompt) is now the `boss-band` plugin in `mods/boss-band/`. This repo is a folder marketplace (`.claude-plugin/marketplace.json`), and the plugin is installed at project scope. `claude plugin list` run in this folder shows it enabled and read from `mods/boss-band`. The user hasn't yet confirmed seeing it on screen after a fresh boss start.
- **`boss-acceptance` skill** (`.claude/skills/boss-acceptance/`) re-runs the definition of done with fixed worker prompts. `scripts/preflight.sh` checks worker count, the git-repo worker and the Claude Code version against Known keys. Tested: it reports NOT READY with one worker.
- **`secret-scan` skill** (`.claude/skills/secret-scan/`): no encryption scheme, full-history scan, plus Anthropic-key and Discord-webhook patterns. The first run was clean.
- **In progress elsewhere:** the NixOS worker is applying the approved skill-audit findings from today's improve-system run (about 17 correctness bugs plus structural fixes in NixOS and global skills). It commits locally and doesn't push without asking. Global skill changes reach `~/.claude` only after `nh os boot` and a reboot.

## Current Goals

**Short-term (next 1-3 sessions)**
- Confirm the band appears on its own after a fresh boss start.
- Relay the NixOS worker's audit-fix report, and get the user's go-ahead before anything is pushed.
- Close the acceptance loose ends: re-run item 5's denied first spawn with the boss watching, and time item 9's 30-second limit.

**Long-term**
- Keep the boss passing `docs/project-brief.md` across Claude Code upgrades. Run `/boss-acceptance` after each upgrade, and update **Known keys** when the version changes.
- Add key mappings for prompt types beyond menus, plans and permission prompts as they're verified.

## Recent Decisions

- **The band loads as a project-scoped plugin, not a hot-reload mod** (2026-10-13). Hot-reload mod folders are keyed by session id, so every boss restart dropped the band. Rejected: a `--plugin-dir` launcher (`bin/boss-claude`, since deleted) and a `~/.zshrc` wrapper (the auto-mode classifier blocked that edit as unauthorized persistence). Also rejected: `CLAUDE_CODE_PLUGIN_DIRS` in global settings, which would load the band in every worker, each polling for a missing `bin/boss-rows` every 2s. Edits to `mods/boss-band/` need only `/reload-plugins`. Never copy the plugin into a hot-reload folder too, or it loads twice.
- **Batch spawn/close behind one approval, one name per line** (the user's preference, 2026-10-13). Per-prompt spawning is only for tests that need some prompts denied.
- **Suggest `/clear`, never run it** (the user's preference, 2026-10-13). Suggest it when a worker's idle hint shows tokens to save. Clear a session only when the user asks.
- **`boss-acceptance` takes guards from CLAUDE.md's Known keys** instead of its own table, so the two can't drift. Its step 10 edit to Known keys is kept as its one non-docs edit. That was chosen over dropping the edit, because the edit records what the run verified.
- **Read-only boss scripts are allowlisted** (`boss-screen`, `boss-pending`, `boss-status`, plus the git-commit/push `status` calls), so relays stop prompting. The `ask` rules on spawn, close and raw kitty commands are untouched.
- **Audit fixes for other repos go to that repo's worker.** The boss fixed only its own `boss-acceptance` and handed the NixOS and global-skill findings to the NixOS worker, with the full list in `~/.claude/improve-system/audit-findings-20261013.md`.
- **The project model is `haiku`** (`.claude/settings.json`). The user switches models with `/model` for heavier work.

## Known Issues / Tech Debt

- **Acceptance item 5, first spawn:** the first `bin/boss-spawn farmer` of the 2026-10-13 run opened a window with no recorded deny step. The later prompts worked, so the lock holds, but that one prompt is unaccounted for.
- **Identical messages get dropped as duplicates:** repeating the exact same text to a worker over SendMessage can be dropped. Reword a repeat request.
- **Item 9's 30-second limit** has not been timed.
- **The 2026-10-13 run skipped "After the boss's `/clear`."** It passed on 2026-10-12.
- **niri window titles** still read `✳ Claude Code`, not the session name. The brief doesn't require them.
- **Absolute paths** to `/home/bosko/projects/boss` in `.claude/settings.json` (marketplace path, allowlist) tie the repo to this machine's layout.
- **`.gitignore` lacks `*.pem` and `*.key`.** Informational: the secret scan notes it, and nothing like that is in the repo.
- **`projects.local.md` lists the boss repo as "none"**, but it now has a public GitHub remote (`CommanderBosko/boss`). The user hasn't said whether to update that gitignored file.
- **An orphaned band copy** sits in `~/.claude/dev-mods/96a9575b…/`. Nothing loads it.

## Next Steps

1. On the next fresh boss start, check that the band shows worker rows without `/reload-plugins`.
2. When the NixOS worker reports, relay what it fixed and skipped, and ask the user about pushing and `nh os boot`.
3. Ask whether to set the boss's Repo column in `projects.local.md` to `CommanderBosko/boss`.
4. Re-run acceptance item 5 (denied first spawn) and time item 9, then record them in a dated `docs/acceptance-*.md`.
