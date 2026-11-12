---
name: are-we-done
description: Audit the current conversation before the user closes the chat session. Checks that every request was finished and verified, nothing is left running, and no work is stranded (uncommitted changes, unpushed commits, open PRs, running delegates, pending drafts). Returns a yes/no verdict, and if no, a numbered step-by-step list of what the user still needs to do. Use when the user says "/are-we-done", "are we done", "can I close this chat", "is everything finished", "anything left?", "safe to close?", or "udah beres semua?".
---

# are-we-done

The user wants to close this chat session. Your job is to tell them, honestly, whether that's safe, and if not, exactly what's left.

This is an audit. Don't start new work, don't fix things, don't run builds. Only run cheap read-only checks. If something needs doing, list it as a step.

## 1. Rebuild the task list from the conversation

Scroll back through the whole conversation and list every request the user made, including small ones mentioned in passing ("and also bump the version"). For each, decide:

- **done**: finished, and there's evidence it works (test passed, command output, screenshot, link)
- **done, unverified**: code changed but never tested, built, or checked
- **partial**: started but not finished
- **not started**: asked for but never touched
- **waiting on user**: blocked on a decision, a secret, an approval, or a manual step only they can do
- **dropped**: the user changed their mind or said to skip it (don't count these as open)

If the conversation was summarized or compacted, you can only see part of it. Use the summary for the earlier requests, and mark the verdict "(partial view)". Never give an unqualified yes on a conversation you can't fully see.

Also catch things you promised but never did ("I'll update the README after"), and drafts you showed the user that still await their yes (PR body, Slack message, GitHub comment). Under the no-posting rule, an approved-but-unsent draft is open.

## 2. Check the real state (read-only)

Run only what applies to this session. Skip anything that clearly doesn't.

Git, for every repo or worktree touched in the session:

```bash
git -C <repo> status --short
git -C <repo> log --oneline --branches --not --remotes   # commits on no remote
git -C <repo> stash list
git -C <repo> branch --show-current
```

Don't use `git log @{u}..HEAD` for the unpushed check. On a branch that was never pushed it errors out and prints nothing, which looks the same as "all pushed". If the repo has no remote at all, say that instead of calling the commits unpushed.

Only flag uncommitted changes as a problem if the user asked for commits, or if the changes would be lost (scratch dir, worktree about to be removed). Otherwise mention them as a heads-up.

PRs created or touched in the session:

```bash
gh pr view <n> --json state,isDraft,mergeable,statusCheckRollup,reviewDecision
```

Flag failing checks, unresolved review comments, or a merge the user asked for that hasn't happened.

Leftover processes (dev servers, browsers, workers):

```bash
find /tmp/claude-dev -name '*.pid' 2>/dev/null | while read -r f; do kill -0 "$(cat "$f")" 2>/dev/null && echo "running: $f"; done
/bin/ps -Ao pid,command | grep -iE "wrangler|workerd|agent-browser|chromium|vite|next dev|esbuild" | grep -v grep
```

The `ps` list covers the whole machine, so most of what it shows belongs to other sessions or to the user. Only flag a process if you can tie it to this session: you wrote its pidfile, you launched that exact command, or it holds a port or `agent-browser --session` name you used. Leave everything else out of the report. Never kill anything during the audit.

Also check, when relevant:

- Background tasks, delegated tasks, or subagents started this session that haven't reported back
- In T3 Code: PRs this thread created or is watching (`list_thread_pull_requests`), and whether a watch should be dropped before closing
- Scheduled tasks, cron jobs, or watched PRs created this session (are they meant to outlive the chat?)
- Temporary files, worktrees, or node_modules that should be cleaned up
- Secrets or env vars that were set locally but not saved where they need to live
- Deploys that were started but not confirmed live

## 3. Report (HARD LIMITS)

The user has ADHD and wants to close the tab. The audit can be long. The reply must be tiny.

Done case: one line, nothing else.

```
Yes, safe to close.
```

Not done case: verdict line, then numbered steps. Nothing before, nothing after except the one-line offer.

```
Not yet.

1. Commit the auth fix in ~/repo.
2. Kill the dev server:
   kill $(cat /tmp/claude-dev/app.pid)

Want me to do 1 now?
```

Hard limits:

- Each step is one short line, max ~10 words. Say what to do, not why
- Max 3 steps. If there are more, list the 3 that matter most, then one line: "+N more, ask if you want them"
- No evidence, no task counts, no status labels, no explanations, no file:line, no PR check details
- No handoff notes, no side issues, no "then you're safe to close", no recap
- Commands go in a code block or indented under the step, nothing else gets a code block
- "done, unverified" becomes a step like "Test the login fix", not a label
- Compacted conversation: add "(partial view)" to the verdict line, nothing more
- No headers, no bold, no em dashes

Before sending, delete every line that isn't the verdict, a step, a command, or the offer.

## 4. Offer to finish

If you can do any of the steps, end with one short question, e.g. "Want me to do 1 and 2 now?". Don't do them until the user says yes.
