# Clean up T3 worktrees

T3 creates one git worktree per thread under `~/.t3/worktrees/<repo>/t3-<id>`, each with its own `node_modules`. They pile up fast (one machine had 26 of them using 5.4 GB). This skill deletes the dead ones without ever losing work.

Everything goes through one script. Never delete a worktree by hand with `rm -rf`, and never pass `--force` to git.

```bash
S=$SKILL_DIR/scripts/t3wt.sh
$S scan                          # dry run: SAFE or KEEP for every worktree, with reasons
$S remove <repo>/<t3-id> ...     # re-checks each one right before removing it
```

## The workflow

1. Run `$S scan`. It changes nothing.
2. Show the user the SAFE rows (size, path, branch, which PR) and a short summary of why the big KEEP ones are kept.
3. Wait for an explicit yes. Removal is a delete, so ask every time, even if they approved a cleanup earlier.
4. Run `$S remove` with exactly the SAFE paths they approved. Never add paths they didn't see.
5. Report what was removed, the space freed (`df -h /System/Volumes/Data`), and the log path.

`remove` runs every check again, so a worktree that changed between scan and remove gets skipped, not deleted.

## What SAFE means

A worktree is SAFE only when every check passes. Any failed or inconclusive check is KEEP. Don't add a flag that weakens one of these, and don't "fix" a KEEP by deleting files to make it pass.

| Check | Why |
|---|---|
| Path is `~/.t3/worktrees/<repo>/<name>` and `.git` is a file | Only linked worktrees. A main checkout can never match |
| On a branch, not detached HEAD | A detached HEAD can hold commits no branch points to |
| Not locked, no rebase/merge/cherry-pick/bisect in progress | Someone is mid-operation |
| `git status` is empty, untracked files included | Uncommitted work |
| Every ignored file is regenerable or already in the main checkout | Catches `.dev.vars`, `.env`, drafts in `.context/` |
| A merged PR whose head is this exact commit, or the commit is in `origin/<default>` | Merged with nothing extra committed after |
| No process has its working directory inside | A shell, dev server, or agent is using it |
| No file changed in the last 120 min (outside `node_modules` and `.git`) | Recent activity |
| Every T3 thread bound to it is archived or deleted | T3 still shows it as live work |

Regenerable ignored paths are build and install output: `node_modules`, `dist`, `build`, `.next`, `.astro`, `.wrangler`, `.turbo`, `.vite-cache`, `.cache`, `*.tsbuildinfo`, logs, plus `.wt.json` (T3's port file) and `.impeccable/hook.cache.json`. The full list is `REGEN_RE` in the script.

Env files (`.env*`, `.dev.vars*`) pass when every line is already in the main checkout's copy, or is a localhost or port line. T3 gives each worktree its own port, so those lines always differ. An extra secret means KEEP. In one repo every worktree had an `AI_GATEWAY_KEY` that the main checkout's `.dev.vars` lacked, and this check is what kept it from being lost. If that's the case again, tell the user the key name (never the value) and let them copy it into the main checkout. Then scan again.

Some keys are made up fresh for every worktree by the repo's own setup, so they always differ and are throwaway. A `wt:setup` script that writes a new `BETTER_AUTH_SECRET` per worktree is an example. List those in `~/.config/t3-skill/per-worktree-keys.txt` (`<repo> <KEY>`, override the path with `T3_PER_WORKTREE_KEYS`), and only with evidence from the repo. `$SKILL_DIR/per-worktree-keys.example.txt` shows the format. Real third-party credentials, like `GOOGLE_CLIENT_SECRET`, never go there.

## Open T3 threads

By default a worktree with any unarchived thread is KEEP. Almost all threads stay unarchived, so the usual fix is for the user to archive the finished threads in T3, then scan again.

To archive them yourself, use the `t3_thread_organize` tool with `action: "archive"`, but only for worktrees whose only blocker is open threads. Archiving a parent thread does not archive its subagent child threads (IDs starting with `thread:provider:`), so list what's still open after the first pass and archive those too. Archiving can be undone with `unarchive`.

`--settled-ok` treats a settled thread (`settledAt` set and not unsettled after it) the same as an archived one. Use it when the user says settled threads are done. All other checks still apply.

`--include-unarchived` lets those through only when every open thread on that worktree has been idle for 24 hours. Use it only when the user asks for it. Note that T3 sometimes bumps `updated_at` on many threads at once (once moving all of them to the same minute), which pushes the idle clock forward.

The thread lookup reads `orchestration_v2_projection_threads` in `~/.t3/userdata/statev2.sqlite`, read-only, matching `payload_json.worktreePath`. If T3 changes that schema, the script says "cannot read T3 state db" and marks everything KEEP. Fix the query rather than skipping the check.

## Undo

`remove` keeps the branch and appends a line to `~/.t3/worktree-cleanup.log` with the repo, path, branch, commit, and the exact restore command:

```bash
git -C <main checkout> worktree add <old path> <branch>
```

Then `pnpm install` in it. The branch's commits are also on GitHub, since SAFE requires a merged PR or the commit being in the default branch.

## Not covered here

- `~/.t3/userdata/statev2.sqlite` is T3's own state. Never touch it.
- `~/.t3/userdata/logs` can be trimmed separately (`find ~/.t3/userdata/logs -type f -mtime +7 -delete`), with the user's OK.

## Requirements

The script uses `$HOME`. If `~/.t3/worktrees` doesn't exist, it says "not found on this machine" and exits. It needs `git`, `gh` (logged in), `jq`, `sqlite3`, and `lsof`, and it's written for macOS bash 3.2.
