# skills

A collection of agent skills for public use. Each skill is a `SKILL.md` file that any agent supporting the skill format can load.

## Available skills

| Skill | Description |
| --- | --- |
| [are-we-done](skills/are-we-done/SKILL.md) | Audits the current session before it is closed. It confirms that every request was completed and verified, that no processes were left running, and that no work remains stranded, such as uncommitted changes, unpushed commits, or open pull requests. It returns a yes or no verdict and, if work remains, a short list of next steps. |

## Installation

Using the [skills CLI](https://github.com/vercel-labs/skills):

```bash
npx skills add zakiego/skills --skill are-we-done
```

Alternatively, clone the repository and copy the skill folder into your agent's skills directory:

```bash
git clone https://github.com/zakiego/skills
cp -r skills/skills/are-we-done <your-agent-skills-directory>/
```

## Usage

Invoke the skill by name (for example, `/are-we-done`) or ask the agent whether the session is complete before closing it.

## Customization

These skills reflect the author's own workflow, including concise responses and a policy of never posting to external services without approval. Adjust them as needed to suit your environment.

## License

Released under the [MIT License](LICENSE).
