# The t3 CLI

One binary, `t3`, runs the server and manages it. It's often not on PATH, so call `~/.t3/bin/t3` (installed version checked: 0.1.9, same subcommand list as the source).

Facts below come from pingdotgg/t3code at commit `fc2b5de20cb572d2333e03284466e3c804d25c84`. The command tree is built in `apps/server/src/binCli.ts`, and each subcommand lives in `apps/server/src/cli/<name>.ts`. Diagnosis commands (`doctor`, `trace summary`, `triage`) are covered in depth by `troubleshoot.md`.

```bash
T3=~/.t3/bin/t3
$T3 --help              # subcommand list
$T3 <subcommand> --help # flags for one
```

## Safety first

If you're an agent inside a T3 thread, you run inside the server these commands control.

| Safe to run from a thread | Needs the user, because it stops or restarts the server |
|---|---|
| `--help`, `--version`, `status`, `status --json` | `t3` / `t3 serve` (starts a second server, refused when one already runs) |
| `thread list/show`, `project add/rename` | `service restart`, `service uninstall`, `service install` |
| `trace summary`, `doctor --dry-run` | `doctor` without `--dry-run`, `update`, `uninstall` |
| `environment list`, `theme show`, `policy show` | `up` when it needs a restart (a restart stops running agent turns) |

`thread start` and `thread send` are safe but have real effects: they start agent turns. `project remove --force` deletes the project and all of its threads. Both need an explicit ask.

## Global flags

`--help`/`-h`, `--version`/`-v`, `--wizard`, `--completions <bash|zsh|fish|powershell|sh|pwsh>`, `--log-level <all|trace|debug|info|warn|error|fatal|none>`.

Almost every subcommand takes `--base-dir <path>`: the T3 data directory, same as `T3CODE_HOME`, default `~/.t3` (`baseDirFlag` in `cli/config.ts`).

## Running the server

| Command | What it does |
|---|---|
| `t3 [cwd]` | Runs T3 Code in this terminal and opens the browser. `cwd` is the working directory for provider sessions |
| `t3 serve` | Same, with no browser, and prints pairing details. The background service runs this |
| `t3 app [path]` | Opens a project in the running desktop app. Default: current directory |

Server flags (`cli/config.ts`): `--mode <web|desktop>`, `--port`, `--host`, `--no-browser`, `--lan` (accept LAN and tailnet connections, same as `T3CODE_LAN`), `--tailscale-serve`, `--tailscale-serve-port`, `--auto-bootstrap-project-from-cwd` (create a project for the cwd when missing, not on `serve`), `--log-websocket-events`, `--dev-url`, `--bootstrap-fd`.

A bare word that isn't a subcommand or an existing directory is rejected as an unknown command. Pass an explicit path such as `t3 ./my-project` for a new directory (`cli/server.ts`).

## Threads from a terminal

`t3 thread` talks to the running server over its MCP endpoint with a short-lived full-access session, revoked when the command ends (`withThreadTools` in `cli/thread.ts`). With no server it fails with "No running T3 Code server uses <base dir>".

```bash
$T3 thread list --project . --json
$T3 thread start . "Fix the flaky login test" --title "Flaky login" --wait
$T3 thread start . "Try the refactor" --worktree origin/main --branch refactor/auth
$T3 thread send <thread-id> "Also update the docs"
$T3 thread show <thread-id> --messages 5
```

| Command | Notes |
|---|---|
| `thread list` | A project's threads, newest first, without subagent threads. `--project` is a project id or a path inside the project, default `.` |
| `thread start <project> <message>` | Prints the new thread id. `--title` (default: the message's first line), `--provider` and `--model` (they go together), `--worktree <branch, tag or commit>` to run in a new worktree instead of the project folder, `--branch` for the new worktree's branch name |
| `thread send <thread> <message>` | Queues the message as the thread's next turn. A busy thread isn't interrupted. Prints `Sent.` or `Queued.` |
| `thread show <thread>` | Title, id, status, provider/model, branch and worktree path, pending answers, then the latest messages. `--messages N`, default 10 |

Shared: `--json` prints JSON, a message of `-` reads stdin, and `--wait` blocks until the agent finishes and prints its reply. With `--wait` the exit code is 1 if the run fails and 2 if it's waiting for an answer.

New threads start at the project's default permission mode, not at the CLI session's full-access ceiling.

## Projects

`t3 project` works against the live server when one runs, and directly against the database when it doesn't (`runProjectMutation` in `cli/project.ts`).

```bash
$T3 project add ~/code/my-repo --title "My Repo"
$T3 project rename <project-id-or-path> "New title"
$T3 project remove <project-id-or-path>          # --force also deletes all its threads
```

`add` refuses a workspace root that's already a project. The folder on disk is never deleted.

## Background service and remote access

| Command | What it does |
|---|---|
| `t3 up` | Sets up remote access and the background service. Asks which routes to allow. `--connect` / `--no-connect` (T3 Connect), `--lan` / `--no-lan`, `--yes` (ask nothing, keep settings), `--headless` |
| `t3 status [--json]` | Service setup and remote access settings. `--json` doesn't test connections |
| `t3 service install` | Installs T3 Code as a background service for this user. `--allow-downgrade` |
| `t3 service restart` | Restarts it. Picks up a version installed by `t3 update`. From inside the service it queues the restart and the session disconnects |
| `t3 service status` | Whether the service is installed |
| `t3 service uninstall` | Stops and removes the service |
| `t3 service protect` | Linux with systemd only: protects the server from agents under memory pressure. `--undo`, `--yes` |
| `t3 connect` | Same as `t3 up --connect`. Subcommands: `login`, `link` (`--publish-only`), `status`, `publish` (`--disable`), `unlink`, `logout` |

`t3 status --json` shape (`setupJson` in `cli/up.ts`):

```json
{
  "service": { "supported": true, "installed": false, "installedVersion": null, "otherBaseDir": null },
  "connect": { "enabled": false, "revoked": false },
  "lan": { "enabled": false, "inheritedDefault": false, "hostOverride": null }
}
```

With `--lan`, anyone on the network can reach the port and a pairing code is the only lock. `t3 service update` is deprecated in favor of `t3 update`.

## Pairing, auth, linked environments

| Command | What it does |
|---|---|
| `t3 pair` | Mints a pairing token for a running server and prints it as a QR code. `--ttl` (default 5 minutes), `--label`, `--tailscale`, `--tailscale-serve-port`, repeatable `--scope` |
| `t3 auth pairing create/list/revoke <id>` | One-time client pairing tokens for headless setups |
| `t3 auth session issue/list/revoke <id>` | Scoped bearer sessions for headless or remote clients |
| `t3 environment link <url> --pairing-code <code>` | Links another T3 machine so agents here can work there. `--url` for extra addresses, `--access` (default `approval-required`) |
| `t3 environment list [--json]` | Linked environments and whether each answers now |
| `t3 environment unlink <id>` | Forgets a link |

A link shows up on the other machine under Settings > Connections, where it can be revoked. Tokens printed by `pair` and `auth` are secrets: don't paste them into chat, issues or logs.

## Updates and install

| Command | What it does |
|---|---|
| `t3 update [version]` | Downloads a newer t3 and switches this machine to it, service included. `--channel`, `--allow-downgrade`, `--yes`/`-y` (required to restart the service from a script) |
| `t3 install` | Installs this version as the `t3` command and prints the PATH line to add |
| `t3 uninstall` | Removes the service, the launcher and every downloaded version. Projects and threads are kept. `--yes`/`-y` required from a script |

## Maintenance and config

| Command | What it does |
|---|---|
| `t3 doctor` | Inspects the data directory and repairs it. `--dry-run` changes nothing, `--fix` applies recommended repairs without asking. Pauses and restarts the service as needed |
| `t3 trace summary` | Counts, rates and latency per span from the local trace file. `--since 30m`, `--limit N` |
| `t3 triage` | Investigates a T3 problem with claude or codex and helps file an issue. `--agent`, `--model` |
| `t3 theme show/set <file-or-id>/clear` | Environment-wide theme. `set --id` publishes a file under another id |
| `t3 policy show/check <file>/templates <dir>` | The administrator's managed policy. `check` validates a file before deploying it |
| `t3 browser setup` | Linux only: prepares the host for T3's headless browser |

Unlisted internal commands exist (`start`, `acp-mcp-bridge`, `acp-mcp-call`, and names starting with `__`). Don't call them by hand.

## Reporting back

Give the user the exact command in a code block, with `~/.t3/bin/t3` spelled out. Say plainly when a command restarts the server, because that ends running agent turns, including the thread that suggested it.
