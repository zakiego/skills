# t3.json reference

`t3.json` sits at the repository root and declares project defaults and shared actions. This file explains what each key means and what T3 does with it. Writing one for a repo is `setup.md`'s job, and it also ships the setup and clean script templates.

Facts below come from pingdotgg/t3code at commit `fc2b5de20cb572d2333e03284466e3c804d25c84`. The schema is `packages/contracts/src/t3ProjectFile.ts`. Source paths are in parentheses.

## Parsing

- File name `t3.json`, schema URL `https://t3.codes/schema/t3.json` (`T3_PROJECT_FILE_NAME`, `T3_PROJECT_FILE_SCHEMA_URL`).
- The parser is lenient: `//` and `/* */` comments and trailing commas are accepted (`fromLenientJson` in `packages/shared/src/schemaJson.ts`, test in `packages/shared/src/t3ProjectFile.test.ts`).
- A missing, unreadable or invalid file never raises an error. The loader logs a warning and behaves as if there were no file (`apps/server/src/project/T3ProjectFileLoader.ts`). So one bad value silently drops the whole file, defaults included.
- The published JSON Schema is built with excess properties as errors (`buildT3ProjectFileJsonSchema` in `packages/shared/src/t3ProjectFile.ts`), so an editor flags unknown keys.

To check a file by hand, look for the warning `Failed to decode t3.json at <path>` in the server trace (see `troubleshoot.md` for where logs live).

## Top-level keys

| Key | Type | Meaning |
|---|---|---|
| `$schema` | string | Schema URL, for editors |
| `iconPath` | string, max 512 chars | Workspace-relative path to the project icon. Checked before T3's built-in icon locations |
| `defaultThreadEnvMode` | `"local"` or `"worktree"` | Where new threads start: the current checkout or a fresh worktree. Built-in default `local` |
| `worktreeSubmodules` | `"recursive"`, `"top-level"`, `"none"` | How new worktrees populate submodules. Built-in default `recursive` |
| `scripts` | array, max 50 | The shared actions |

All keys are optional.

## Action keys (`scripts[]`)

| Key | Type | Meaning |
|---|---|---|
| `name` | string, required | Label in the actions menu |
| `command` | string, required | Shell command typed into a T3 terminal |
| `icon` | `play`, `test`, `lint`, `configure`, `build`, `debug` | Menu icon. Default `play` |
| `runOnWorktreeCreate` | boolean | Runs automatically after a worktree is created for a new thread |
| `async` | boolean | Only for `runOnWorktreeCreate`. `true` (default): the agent starts while the script runs. `false`: the agent waits for it to exit |
| `runOnSettle` | boolean | Runs in the thread's worktree each time the thread settles |
| `stopOnSettle` | boolean | T3 stops this action's terminal and child processes when its thread settles |
| `previewUrl` | string | URL opened in the in-app browser preview when the action runs. Desktop build only |
| `autoOpenPreview` | boolean | Opens the preview panel at `previewUrl` the moment the action starts |

`name` and `command` are trimmed and can't be empty.

## Who wins: the override chain

Settings that `t3.json` can declare resolve in this order (`docs/user/project-settings.md`, Defaults and inheritance):

1. the project override in T3 settings
2. the environment setting
3. `t3.json`
4. the built-in default

That covers `defaultThreadEnvMode` and `worktreeSubmodules` (`PROJECT_FILE_BACKED_SETTINGS` in `packages/contracts/src/t3ProjectFile.ts`). A setting has to be on Inherit in both the project and the environment for the file's value to apply. For `worktreeSubmodules`, the `t3.json` of the branch being checked out is the one read. If that file is invalid, T3 logs a warning and falls back to recursive (`apps/server/src/vcs/GitVcsDriverCore.ts`).

Actions are different. T3 doesn't run them from the file. The runner uses the project's saved action list, resolved in this order (`resolveProjectScripts` in `packages/shared/src/projectScripts.ts`): the project's own list in settings, then the environment's shared default list, with the project record's own scripts as a legacy fallback. `t3.json` actions get into that list by being imported in Settings > Projects > Actions. An action that exists only in the file does nothing automatically.

To see what T3 will really run for a project, read the saved scripts with the `t3_project_read` MCP tool, not the file.

## How an action runs

From `apps/server/src/project/ProjectSetupScriptRunner.ts`:

- Which one. The setup action is the first saved script with `runOnWorktreeCreate`. The settle action is the first with `runOnSettle`. Extra ones are ignored (`setupProjectScript`, `settleProjectScript`).
- Where. A T3 terminal owned by the thread, with the worktree as the working directory. Terminal id `setup-<scriptId>` for setup, `settle-<scriptId>-<random>` for each settle run, so a settle never types into a shell that's still busy from an earlier one.
- How. T3 waits for the shell prompt, then types the command with a leading space (so shells with ignore-space history skip it) and Enter.
- Environment. `T3CODE_PROJECT_ROOT` is the project's main checkout. `T3CODE_WORKTREE_PATH` is the worktree, set only when there is one. T3 also sets `COLORTERM=""`, `NO_COLOR=1` and `FORCE_COLOR=0` (`projectScriptRuntimeEnv` in `packages/shared/src/projectScripts.ts`).
- Shell startup prompts. If an rc file asks a question at startup (fnm, nvm), T3 holds the command until the shell is ready. No one is attached to answer, so a prompting rc file or a prompting install stalls the action.
- Exit code. When T3 watches for completion, it wraps the command in a subshell and prints a random sentinel with `$?`. On exit code 0 it closes the idle terminal. `cmd.exe` isn't supported for this (PowerShell is).

## Setup action: what `async` changes

From `apps/server/src/orchestration-v2/ThreadLaunchService.ts`:

- It only runs when the thread has a worktree. A thread in the main checkout runs no setup action.
- `async: false`: the launch waits. A non-zero exit fails the launch with "Setup script exited with <code>", so the agent never starts on a broken checkout.
- `async: true` or unset: the agent starts right away and the result is recorded as done or failed afterwards.
- Output lines are captured into the thread's setup progress (lines cut at 400 chars).
- `t3_worktree_handoff` runs the same setup action in the new worktree by default (`apps/server/src/mcp/WorktreeMcpService.ts`).
- A thread started by a linked environment below full access skips the setup action: the script is the user's own code and such a link only grants T3's tools (`skipped-for-link`).

## Settle: what happens

From `cleanUpSettledThread` in `apps/server/src/orchestration-v2/ThreadSettlementService.ts`:

1. Terminals opened by actions with `stopOnSettle` are closed, along with their child processes (`closeOnSettle` in `apps/server/src/terminal/Manager.ts`). This only covers a terminal started through that action, not a server the agent started in its own shell.
2. If the thread has no worktree, or the worktree folder is gone, nothing else happens.
3. The settle action runs once per settlement. A thread that's re-engaged before cleanup isn't cleaned up.
4. A subagent that shares its parent's worktree skips the settle action. The worktree belongs to the parent.

## Quick diagnosis

| Symptom | Likely cause |
|---|---|
| Whole file ignored | Invalid value somewhere (wrong enum, empty `name`, over 50 scripts). Check the server warning |
| Action never runs automatically | Not imported into the project's actions, or a project or environment list overrides it |
| Setup ran but agent started without deps | `async` unset. Set `"async": false` |
| Thread fails at launch | Blocking setup exited non-zero. Open the `setup-<id>` terminal output |
| Setup hangs forever | Install or rc file waiting on a prompt with no terminal attached |
| Second setup or settle action ignored | Only the first of each kind is used |
| Settle action didn't run | Thread has no worktree of its own, or it's a subagent sharing the parent's |
| `previewUrl` does nothing | Not the desktop build |
| `defaultThreadEnvMode` ignored | A project or environment setting isn't on Inherit |

## Example

```jsonc
{
  "$schema": "https://t3.codes/schema/t3.json",
  "iconPath": "public/favicon.svg",
  "defaultThreadEnvMode": "worktree",
  "worktreeSubmodules": "none",
  "scripts": [
    { "name": "Setup Worktree", "command": "bash scripts/setup-worktree.sh", "icon": "configure", "runOnWorktreeCreate": true, "async": false },
    { "name": "Clean Worktree", "command": "bash scripts/clean-worktree.sh", "icon": "configure", "runOnSettle": true },
    { "name": "Dev", "command": "pnpm dev", "icon": "play", "stopOnSettle": true, "previewUrl": "http://localhost:3000", "autoOpenPreview": true }
  ]
}
```
