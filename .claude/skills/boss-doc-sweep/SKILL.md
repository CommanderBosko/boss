---
name: boss-doc-sweep
description: After an architecture change in the boss project (e.g. kitty to herdr, removing the worker band), find and fix every stale reference to the old term across code, docs, memory and skills, then commit. Use when the user says "sweep the docs for X", "remove references to X", "update all docs after the change", "clean up stale references", or "doc sweep".
---

# Boss Doc Sweep

Searches the boss project's code, docs, skills and memory for the old term(s) of an architecture change, rewrites or deletes every stale reference, confirms zero stale hits remain, then commits the sweep's files once the user approves the list. (Bucket: Orchestration)

Run it from `~/projects/boss`. A sweep edits only this folder and the project's memory dir. It never edits another project, and it never pushes.

## Steps

### 1. Fix the terms and warn about prompts
- Take the old term(s) from the invocation. If none were given, ask with AskUserQuestion which change this is, offering the subjects of `git log --oneline -5` as options (free text via Other).
- Add the obvious sibling identifiers (script, plugin and folder names, e.g. `band` also means `boss-band`, `boss-rows`, `mods/`) and tell the user which you added. Prefer the specific identifier when the bare term is a common word.
- Read `.claude/settings.json` and compare each term with `permissions.ask`. Those `Bash(*...*)` globs match *anywhere* in a command, so a term such as `boss-spawn`, `send-text`, `send-key` or `tab create` makes the grep itself raise a native permission prompt. If any term matches, say so before running it: the prompt is a read-only grep tripping the lock, and the user must approve it. The step 5 re-check and a commit message that names the term trip the same rule, so expect up to three prompts. Put the reason in each Bash call's `description` (the native dialog shows it). Don't split or quote the term to dodge the rule.

### 2. Find the hits
Run `.claude/skills/boss-doc-sweep/scripts/find-stale.sh <term>...`. It prints hits grouped by file, then the file *names* that contain a term. It skips `docs/acceptance-*.md` (dated records) and says how many hits it skipped. Pass `--include-acceptance` only if the user asks for those too. Exit 0 means nothing to do: say so and stop.

### 3. Read everything, then triage and edit
- Read **every** file with hits in full, in one pass (Read Everything Before Editing), before the first edit. Include `CLAUDE.md`, `.claude/settings.json` and the memory files.
- Classify each hit, then edit all the files:
  - **Stale** (now false or dead): rewrite it to what is true now, or delete the line or section if the thing is gone.
  - **Intentional leftover** (keep, and list it in the report): a fallback that still exists (kitty still serves non-herdr workers, so only fix claims that say kitty is *the* path), and dated history.
  - **Dated history**: leave `session-summary.md` entries alone. In `project-state.md`, update the current-state and next-step sections, drop goals that depended on the dead thing, and mark an old decision `(superseded <date>)` with a line saying what replaced it instead of deleting it.
  - **Removed features**: where `CLAUDE.md` described one, replace the bullet with one line saying it was removed, when and why, and not to bring it back (as the 2026-11-09 band removal did). Don't leave the old description.
- Edit rules for what the project guards:
  - `bin/boss-hook` must still print nothing on any event except SessionStart. Never add output while editing it.
  - Never loosen an `ask` or `allow` rule in `.claude/settings.json` for something that still exists. Remove rules only for scripts you delete. Run `jq empty .claude/settings.json` afterwards.
  - Run `bash -n` on every script you edit.
- After editing `CLAUDE.md`, run `.claude/skills/boss-acceptance/scripts/preflight.sh` and report its exit code. It parses the `**Known keys** (verified on Claude Code <version>)` line, so `Known keys verified on: ?` in its output means the sweep broke that line: fix it. Exit 1 (too few workers), 2 (no live boss) and 3 (version changed) don't come from the sweep, but still report them.

### 4. Delete what is dead
- Tracked dead files and folders: `git rm -r <path>`. Then `ls` the parent: ignored leftovers such as `mods/` can stay on disk. Remove an empty directory with `rmdir`, and name anything non-empty to the user instead of deleting it.
- Memory files about the dead thing: list them, one line of reason each, and ask with AskUserQuestion (Delete / Keep) before deleting, since memory isn't in git and can't be recovered. Then `rm` each file and remove its pointer line from `MEMORY.md`. A memory file that is only partly stale gets an Edit, not a delete.
- If a Claude plugin or marketplace was involved (`.claude-plugin/`, `enabledPlugins` or `extraKnownMarketplaces` in `.claude/settings.json`), **ask first** with AskUserQuestion, then run `claude plugin uninstall <plugin>@<marketplace> --scope project` and `claude plugin marketplace remove <marketplace>`. They also drop the emptied keys from `settings.json`, so Read it again before editing it by hand. The plugin stays loaded in the running boss until `/reload-plugins` or a restart: tell the user.

### 5. Confirm zero stale hits
Re-run `find-stale.sh` with the same terms (`--include-acceptance` only if step 2 used it). Expect `CLEAN` and exit 0. Anything left must be a deliberate leftover from step 3: list each file with the reason. Otherwise go back to step 3.

### 6. Commit, with the user's go-ahead
- Run `git status --short` and show the user the sweep's files: edited, deleted, and memory changes (the memory dir is outside the repo, so those can't be committed). Ask with AskUserQuestion: **Commit these** / **Change the list** / **Don't commit**. Never commit without the answer.
- If the status shows changes the sweep didn't make, leave them out and name only the sweep's files.
- Commit with `/home/bosko/.claude/skills/git-commit/scripts/git-commit.sh commit <file>...`, passing the message on stdin as that skill's SKILL.md shows: a subject in the repo's style that names the change and why, and the attribution trailer the session's instructions give. Don't push.
- If the sweep used `git rm`, that script fails with `fatal: pathspec '<path>' did not match any files`. Use `git add -- <the files that still exist>`, then `git commit -F - -- <every file, removed ones too> <<'EOF' ... EOF`.

### 7. Report
List the terms searched, the files edited, deleted and left as deliberate leftovers (with reasons), the memory files changed, the `preflight.sh` result, the final `find-stale.sh` result, and the commit hash and subject. Remind the user to `/reload-plugins` if a plugin was uninstalled.

## Arguments

- `<term>...`: the old term(s), space separated; quote a term that contains a space. Several terms are OR'd.
- `--include-acceptance`: also scan the dated `docs/acceptance-*.md` records.

## Gotchas

- **Common words are noisy.** A sweep for `band` also hits unrelated prose. Read each hit's context before changing it, and search the specific names (`boss-band`, `boss-rows`) too.
- **A fallback is not stale.** After the move to herdr, kitty is still the path for workers without `HERDR_PANE_ID`, so most `kitty` hits in `bin/` and `CLAUDE.md` are correct. Fix only claims that are now false.
- **`git rm` breaks `git-commit.sh commit`.** Its `git add --` can't take a path that is already gone (checked in a scratch repo). Use the fallback in step 6, or delete with plain `rm` and let the script stage the deletion.
- **Memory edits aren't undoable.** The memory dir isn't a git repo, so delete there only after the user says yes, and never pass memory paths to `git-commit.sh`.
- **The sweep skips its own folder.** `find-stale.sh` ignores `.claude/skills/boss-doc-sweep/`, because this skill's text names example terms.

## Scripts

- `scripts/find-stale.sh <term>...`: read-only. Case-insensitive fixed-string search over `bin/`, `CLAUDE.md`, `README.md`, `project-state.md`, `session-summary.md`, `mods/`, `.claude-plugin/`, `.claude/settings.json`, `.claude/skills/`, `docs/` and the project's memory dir, grouped by file, plus file names containing a term. Skips `docs/acceptance-*.md` unless `--include-acceptance`. Exit 0 clean, 1 hits, 2 usage error. Called in steps 2 and 5.
