# skills

Agent skills I use day to day and figured were worth sharing. They're written for Claude Code but work in any agent that reads `SKILL.md` files.

## Skills

| Skill | What it does |
| --- | --- |
| [are-we-done](skills/are-we-done/SKILL.md) | Audits the chat before you close it. Checks that every request got finished, nothing is still running, and no work is stranded (uncommitted changes, unpushed commits, open PRs). Answers yes or no, and if no, gives you up to 3 steps. |

## Install

With the [skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add zakiego/skills --skill are-we-done
```

Or copy the folder by hand:

```bash
git clone https://github.com/zakiego/skills
cp -r skills/skills/are-we-done ~/.claude/skills/
```

Then type `/are-we-done` or ask "are we done?" before closing a session.

## Notes

These come straight from my own setup, so a few assume things about how I work (terse replies, no auto-posting, T3 Code tools). Tweak them to fit yours.
