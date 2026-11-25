---
name: what-now
description: Tell the user exactly what to do next, as a tiny numbered checklist with no extra words. Steps in the right order, parallel ones grouped, gates marked, full PR links. Any step the user does by hand gets a click-by-click guide with the exact link to open, what to type, fill, or upload, and what "done" looks like. Ends with "reply done", so the agent checks the result itself before the next round. Offers to do the steps the agent can do itself, and runs them only after the user says yes. Use when the user says "/what-now", "what should I do", "what do I do now", "what's next", "give me the steps", "what do I click", or seems lost in a long thread.
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
- For every user step, find the real details before writing it: the exact URL (from the app's routes, config, docs, or a web search), the button and field names as they appear on screen, the value to type, the file to upload, and what the screen shows once it worked. Never send a vague location like "on Connectors" or "in settings". If you can't confirm a URL or label, say so on that line instead of guessing.

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

User steps that need more than one click get a guide. Keep the task line short in `Do now:`, then put the click-by-click guide under it:

````
Status: notifications are paused, two connectors missing.

Do now:
1. Add the Calendar feed connector (guide A).
2. Link WhatsApp to the inbox connector (guide B).

Guide A: Calendar feed
1. Open https://calendar.google.com/calendar/r/settings
2. Left sidebar: click your calendar under "Settings for my calendars".
3. Scroll to "Secret address in iCal format", click the copy icon.
4. Open https://app.example.com/connectors, click "Add" on Calendar feed.
5. Paste into "Feed URL", click "Save".
Done when: Calendar feed shows "Connected".

Guide B: WhatsApp inbox
1. Open https://app.example.com/connectors, click "Add" on WhatsApp inbox.
2. Type your number in "Phone", click "Get pairing code".
3. Phone: WhatsApp > Settings > Linked devices > Link a device.
4. Tap "Link with phone number instead", type the code.
Done when: WhatsApp inbox shows your number.

Reply "done".
Next: I write the prompt, test it, then switch it on.
````

Guide rules:

- One-action steps stay inline, no guide: `Open <url>, click "Merge".`
- A guide covers every screen: the URL to open, where to click (exact label in quotes), what to type, what to upload.
- A value the user types that you know (a URL, a name, a config line): its own code block so it can be copied.
- A file to upload: its absolute path.
- A secret the user pastes into a third-party app: tell them where to copy it from and where to paste it. A secret the agent needs itself: ask through a secure secret prompt if the host has one, never in chat.
- End each guide with `Done when:` and what the screen shows on success.
- Guide lines max 15 words, verb first. Short guides (3 lines or less) can sit right under their task instead of after all tasks.

Word budget:

- `Status:` is optional, one line, max 12 words. Only when the state changed or explains the steps. Never a list of evidence, never "so probably...".
- Each `Do now:` step max 12 words. Verb first. One action. Detail goes in its guide, not the step.
- `Wait:` one line: what and how long.
- `Next:` one line, max 10 words.
- Leave-alone warnings fold into `Next:` or a step, never their own paragraph.
- Nothing else. No intro, no reasoning, no bullets, no "why", no headers (the `Guide A:` label lines are fine). If they want why, they'll ask.

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
