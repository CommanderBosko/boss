---
name: secret-scan
description: Triggers when the user says "secret scan", "scan for secrets", "check for leaked secrets", "is it safe to push", "any secrets in the repo", or "pre-public check". Read-only scan of the working tree and full git history for plaintext secrets, tuned to this project's no-scheme, gitignored-local-files setup.
model: haiku
version: 0.1.0
---

# Secret Scan

A read-only guard that scans the **working tree and full git history** for plaintext
secrets before a push or before changing repo visibility.

## Arguments

None.

## What it knows about this project

- **Secret-management scheme:** none. The boss uses no credentials. Anything private stays in gitignored local files: `projects.local.md` (names private repos and family projects), `colors.conf`, `.claude/settings.local.json`, and any `.env`. The committed `*.example` copies hold placeholders only.
- **Encrypted/managed secret locations:** none. The repo has no sops, git-crypt or `secrets/` directory, so pass 2 is a no-op.
- **Paths excluded from pattern matching:** `.claude/skills/` only, since this skill's own docs contain example patterns. There are no fixtures or vendored code to skip.
- **Known intentional non-secrets (don't flag these):** runtime paths such as `$XDG_RUNTIME_DIR/claude-boss/` and `/run/user/1000/cc-socks/<pid>.sock`, `uds:` peer addresses, claude pids in `docs/acceptance-*.md`, palette hex colors (`#rrggbb`) in `bin/lib.sh` and the docs, and `claude.ai/artifact/...` links. Artifact links are private to their owner and grant no access.
- **Full git-history scan:** yes. The repo is small (a handful of commits, under 1MB), so every run scans all commits.

## Instructions

1. Run `scripts/secret-scan.sh`. It performs four passes:
   - **Working tree** — high-signal patterns (private-key blocks, password hashes,
     GitHub/AWS/Slack tokens, plus Anthropic API keys and Discord webhook URLs) across tracked files, excluding the
     configured paths.
   - **Encrypted-secret integrity** — skipped: this project has no encryption scheme, so the script prints a skip line. That is expected, not an error.
   - **Git history** — the same high-signal patterns across *all commits* (catches
     secrets that were committed then removed but still live in history). Prints
     `commit:path` hits. Any hit here matters even if the tree is clean, because the repo is pushed to GitHub.
   - **.gitignore coverage** — informational check that common secret-file extensions
     are ignored.

2. Report the result. If **clean**, say so plainly. If there are findings, present each
   with its location and the right remediation:
   - **Plaintext secret in the working tree** → remove it from the tracked file. If the value is needed locally, move it to a gitignored file (`.env`, or a `*.local.*` file listed in `.gitignore`) and commit only a placeholder `.example` copy. Rotate the credential if it was ever pushed.
   - **Unencrypted managed-secret file** → not applicable here: there are no managed-secret files. If a secret file shows up tracked, `git rm --cached` it and add it to `.gitignore`.
   - **Secret found in history** (but not the tree) → it was removed but persists in past
     commits. Removing it now is **not** enough for a public repo — rewrite history with
     `git filter-repo --replace-text` (replace the literal with a redaction marker), then
     force-push, then realign other clones (`git fetch && git reset --hard origin/main`).
     Consider rotating the leaked credential regardless.

3. The history pass scans every commit, so on a large repo it can take a little time — tell
   the user it's working if it pauses.

## Notes

- Purely read-only; never modifies files or git state.
- Pattern-based, so it's a strong guard, not a proof of absence. Treat a clean result as
  "no high-signal leaks found," and still apply judgment for project-specific secrets.
- To add a new secret pattern, edit `EXTRA_PATTERNS` in `scripts/secret-scan.sh`.

## Script

```
scripts/secret-scan.sh
```
