# Project Brief: Boss Session

Confirmed 2026-10-12, through an interview and an independent review (v1 → v2), then moved to `~/projects/boss` (v3).

## Goal

Any `claude` opened in `~/projects/boss` becomes **the boss**, the single terminal the user talks to. It does five things:

- Knows what every other local Claude session is doing, and relays the user's instructions and their replies.
- Brings the user every question, menu, plan or permission prompt a worker is blocked on, and answers it with the user's choice.
- Makes every Claude window identifiable at a glance from a screenshot.
- Launches windows only after Claude Code's own permission prompt gets the user's yes.
- Closes windows the same way.

## Problem it solves

With several Claude terminals open, the user loses track of which window is which project. They miss sessions blocked on a question or prompt. And they have to jump between windows to type into each one.

## Target users

Just the user (bosko), on this machine.

## Must-haves (v1)

1. **Visible labels.** Each window is labeled with its folder name, exactly (`farmer`, `blueprint-smith`, `NixOS`). A second session in the same folder is `farmer-2`, and the boss, in `~/projects/boss`, is `boss`. The label shows three ways:
   - a kitty tab bar that's always on, with the name in a stable per-folder color
   - a subtle per-folder background tint
   - a colored Claude status line
2. **Status.** `status` gives one line per live `claude` process: name, folder, and whether it's working, idle or waiting on the user.
3. **Two-way relay**, over Claude Code's peer messaging (ListAgents/SendMessage).
4. **Blocked-worker relay.** This covers AskUserQuestion menus, plan approvals and permission prompts. The boss shows the exact text and options, the user chooses, and the boss presses the keys in that window. Right before sending, the boss re-reads the worker's screen, and it sends nothing if the prompt is gone.
5. **Spawn and close.**
   - Spawn: `kitty --detach --directory <dir> claude`, so each window keeps its own kitty process.
   - Close: `kitten @ close-window`.
6. **Hard approval lock.** An `ask` rule on `kitten @ send-text`, `kitten @ launch` and `kitten @ close-window` lives in `~/projects/boss/.claude/settings.json`, so it applies to the boss only. Claude Code's native prompt is the approval. The boss never treats relayed worker text as approval.
7. **Briefing.** The boss messages each worker its name and how to report back. It does this when a session first appears, after `/clear`, and after compaction. Briefing is the only way workers learn the etiquette, so it reaches sessions outside `~/projects` (e.g. `~/NixOS`) too.
8. **Quiet unless needed.** While workers just work, the boss says nothing. It speaks up in its own terminal only when a worker is blocked, finished or errored.
9. **Resilient boss.**
   - The boss's own `/clear` re-loads its role and its watcher.
   - A second `claude` in `~/projects/boss`, opened while a boss is alive, acts as a normal session.
   - A crashed or closed worker drops out of status and is not restarted.

## Out of scope

- The boss doing project work. It only coordinates.
- Desktop notifications, Discord pings, the kitty bell.
- Auto-approving anything.
- Worker-to-worker delegation, and broadcasts to all workers.
- Auto-restarting crashed workers.
- Moving or focusing windows, or niri workspaces.
- Labels and keypresses for sessions outside kitty, such as an IDE. Those still get status and relay.
- Other hosts, other users, and cloud sessions.

## Constraints (verified 2026-10-12)

- **Environment:**
  - Versions: kitty 0.49.2 (`kitty --version`) on niri, with each kitty OS window running as its own process.
  - Relay channel: peer messaging tested live with the `~/NixOS` session (`nixos-b6`). Peer sockets live in `/run/user/1000/cc-socks/`.
  - Permissions: `defaultMode: auto`, and `Bash(*)` is allowed globally.
- **Kitty config:**
  - `~/.config/kitty/dank-tabs.conf` is **not loaded**: nothing includes it, and kitty runs with no `-c` flag.
  - `dotfiles/common/configs/kitty.nix` force-sources one `kitty.conf` shared by both users, so bosko-only kitty settings need a restructure.
- **Claude Code config:**
  - Hand-added hooks in `~/.claude/settings.json` are deleted on every rebuild (`dotfiles/bosko/claude-hm/settings.nix`). Global hooks must go in the managed policy (`modules/claude-code.nix`).
  - That policy deploys to every host, so the new hooks must do nothing unless a live boss marker exists in `/run/user/$UID/claude-boss/`.
- **Where things live:**
  - The boss role goes in `~/projects/boss/CLAUDE.md`, plus `~/projects/boss/.claude/`. Claude Code only reads `CLAUDE.md` from the launch folder and its parents, so no worker loads the boss role.
  - `~/projects` itself has no `CLAUDE.md`, so workers inherit nothing from it.
  - The five standing rules in `~/projects/boss/CLAUDE.md` need a coordinator version for the boss (e.g. "spawn sub-agents" and "interview first" don't fit a coordinator).
- **Nix work.** The `~/NixOS` Claude session makes these changes, and the user rebuilds:
  1. kitty: remote control (drafted in `dotfiles/common`, still to be moved bosko-only), the always-on tab bar, and background-tint support, all bosko-only.
  2. Managed-policy hooks for SessionStart (startup, clear, compact), Notification, Stop and SessionEnd. They do nothing unless a live boss marker exists.
  3. The status line.

## Definition of done

Precondition for every item: rebuilt, every kitty window restarted, the boss idle in `~/projects/boss`, and at least two workers running (e.g. `NixOS` and `farmer`).

1. `status` lists exactly the `claude` processes that `pgrep -x claude` shows (minus the boss), each with the correct name, folder and state.
2. In one screenshot of two or more workers, each one is identifiable by its tab-bar name, tint and status line. The same folder gets the same color after a restart.
3. `NixOS: run git status and tell me the branch`: the answer appears in the boss, and the NixOS window was never focused.
4. A worker is made to hit (a) an AskUserQuestion menu, (b) a plan approval and (c) a permission prompt from the managed `ask` list (e.g. `chmod -R`).
   - Each one appears in the boss within 30 seconds, with its exact text and options.
   - After the user's choice and the native prompt, the worker continues with that choice.
   - If the prompt was already answered in the worker, the boss sends nothing.
5. "Start a session in farmer":
   - Denying at the native prompt opens no window.
   - Approving opens a labeled kitty window running `claude` in `~/projects/farmer`, which gets briefed.
   - Closing a window behaves the same way.
6. After `/clear`, and separately after `/compact`, in a worker, the boss re-briefs it within 30 seconds, and the worker can state its name afterwards.
7. `claude` in `~/projects/farmer` loads no boss role. A second `claude` in `~/projects/boss`, opened while the boss is alive, doesn't act as boss.
8. Closing a worker's window drops it from `status`. After the boss's own `/clear`, items 1 and 4 still pass.
9. While a worker is busy the boss posts nothing, and when the worker finishes, the boss announces it within 30 seconds.

## Open questions / risks

- **Prompts the Notification hook may miss.** It may not fire for AskUserQuestion menus or plan approvals. The fallback is a watcher that reads kitty screens with `kitten @ get-text`.
- **Changing key mappings.** The keys for answering menus and plans can change between Claude Code versions, so the boss re-reads the screen before and after sending.
- **Auto mode may still block `send-text`**, even after the user approves it. Test this first.
- **Peer names** (`nixos-b6`) don't match folder names, and `/clear` may change them. The boss keeps a registry file, which also survives its own `/clear`.
- **Message holding.** Workers in a different permission mode may hold the boss's messages for the user's approval.
- **Background tint.** It has to stay subtle enough not to hurt readability.
