---
name: what-now
description: Tell the user exactly what to do next, as a tiny numbered checklist with no extra words. Steps in the right order, parallel ones grouped, gates marked, full PR links. Ends with "reply done", so the agent checks the result itself before the next round. Offers to do the steps the agent can do itself, and runs them only after the user says yes. Use when the user says "/what-now", "what should I do", "what do I do now", "what's next", "give me the steps", "what do I click", or seems lost in a long thread.
---

# what-now

The user may be on a phone, busy, or tired of long text. Every extra word is a cost. Give the bare checklist and nothing else.

## 1. Check the real state (read-only)

Find open work in the thread (PRs, deploys, CI, delegates, approvals), then check what's true now. Don't guess from memory.

```bash
gh pr view <n> -R <owner/repo> --json url,state,isDraft,mergeable,statusCheckRollup
gh run list -R <owner/repo> -L 3
```

Do nothing else until the user says yes.

## 2. Sort and order

- Agent can do it: anything runnable from here (commands, deploys, `gh pr merge`, CI reruns, messaging another thread). Never hand the user a command you could run.
- Only the user: secrets, browser or app actions, their own decisions.
- Independent steps go in one round. If B needs A, B waits for a later round.
- A round ends at a gate (deploy, CI, a delegate, a check). Show only the current round.

## 3. Output (strict)

```
Status: no request has reached the new API yet.

Do now:
1. Open https://example.com/admin, run 1 test request.
2. Merge #215: https://github.com/owner/repo/pull/215
3. Redeploy the API (I can do this)

Wait: deploy, ~20 min.

Reply "done".
Next: merge #217.
```

Word budget:

- `Status:` is optional, one line, max 12 words. Only when the state changed or explains the steps. Never a list of evidence, never "so probably...".
- Each step max 12 words. Verb first. One action.
- `Wait:` one line: what and how long.
- `Next:` one line, max 10 words.
- Leave-alone warnings fold into `Next:` or a step, never their own paragraph.
- Nothing else. No intro, no reasoning, no bullets, no "why", no headers. If they want why, they'll ask.

Formatting:

- "Do now" steps are parallel unless a step says "After 1:".
- PRs: full URL on the same line, never just "#70".
- A command the user must run: its own code block, one command, no `&&`.
- A GitHub button action: link plus button names, no command.
- A message for another thread: thread link plus code block.
- Match the user's language.

Agent steps:

- Mark with `(I can do this)`, name the action, no command.
- Ask once with AskUserQuestion: "Do it for me (Recommended)" / "I'll do it myself". Without it: `Reply "yes" and I'll do 3.`
- After yes: do it, wait for the gate yourself, verify, then give the next round.

Check-in:

- Only when the round has user steps. Just `Reply "done".`
- Never a sentence to copy, never a placeholder to fill. You find the result yourself (PR state, logs, database, storage).

## 4. When the user says "done"

Verify it really happened. Missing something: one line ("#215 still open"), repeat that step only. All good: next round, same format.

## 5. Nothing to do

One line: "Nothing for you. Deploy running, I'll ping when done."
