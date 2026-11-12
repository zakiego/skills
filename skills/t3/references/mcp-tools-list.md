# T3 Code MCP tools, by toolkit

Every tool the `t3-code` MCP server registers, from pingdotgg/t3code at commit `fc2b5de20cb572d2333e03284466e3c804d25c84`. 72 tools across 12 toolkits. Paths are relative to `apps/server/src/mcp/toolkits/`. Input shapes that aren't inline in `tools.ts` are in `packages/contracts/src/orchestratorMcp.ts`.

"RO" marks tools annotated read-only. Most tools that take `environmentId` forward the call to a linked machine, where ids are that machine's.

## orchestrator (`orchestrator/tools.ts`, 20 tools)

| Tool | What it does |
|---|---|
| `orchestrator_capabilities` (RO) | Providers, models, options and runtime modes for `delegate_task`. Short list. `search` finds other models |
| `delegate_task` | Starts one child agent with only `task`. No parent history |
| `task_status` | Reads one delegated task you started. Reading a finished `summary` marks it delivered |
| `task_cancel` | Stops a delegated task: its running and queued turns, its own delegates and its PR watches |
| `t3_workflow_stop` | Stops a running Claude workflow in a thread by `subagentId`. The thread keeps going |
| `t3_background_wait` (RO) | Keeps this thread in Working while background tasks run. 1 to 20 `taskIds`. `waiting=false` clears. Claude only |
| `schedule_task` | Creates scheduled work, or updates one when `scheduledTaskId` is given |
| `list_scheduled_tasks` (RO) | Lists scheduled tasks for a project |
| `delete_scheduled_task` | Deletes one scheduled task. Permanent |
| `request_secret` | Asks the user for one secret in a card |
| `create_threads` | 1 to 20 new top-level threads in this checkout |
| `t3_thread_list` (RO) | Threads newest first, in one project or `allProjects`. Filters: `statuses`, `titleContains`, `settled`, `snoozed`, `includeSubagents` |
| `t3_thread_read` | Any thread by id. `view`: `messages` (default) or `activity`. `limit` 1 to 100, `runLimit` 1 to 50, `maxCharsPerItem` 1 to 50000 |
| `t3_thread_update` | `action: "rename"` with `title`, or `regenerate_title` |
| `t3_thread_send` | Sends a message. `mode`: `auto`, `queue`, `steer`, `restart`. `freshContext` starts a new provider session, like /clear |
| `t3_thread_wait` (RO) | Waits for a run to finish. `untilDelegatedWorkSettled` also waits for its delegates and background tasks |
| `t3_thread_interrupt` | Interrupts a top-level thread's running turn |
| `t3_environment_links` (RO) | Linked machines and whether each answers now |
| `t3_environment_link` | Asks the user, in a card, to link another machine. Returns `pending` |
| `t3_environment_unlink` | Forgets a linked machine |

The three `t3_environment_link*` tools are hidden while linked environments are off (`hiddenWhileLinksOff` in `apps/server/src/mcp/McpInvocationContext.ts`).

## thread (`thread/tools.ts`, 7 tools)

| Tool | What it does |
|---|---|
| `run_scheduled_task_now` | Runs one scheduled task now. Needs a full-access or default caller. Success means started, not finished |
| `t3_thread_search` (RO) | Searches active threads by title, branch, PR, project, then message text. Skips subagent threads. Not exhaustive |
| `t3_thread_configure` | Reads a thread's provider, model and modes, or sets provider, model and options with `modelSelection`. Permission modes stay |
| `t3_thread_transfer` | `fork` (copy context into a new thread, no turn runs), `merge_back` (into a related `targetThreadId` in the same project), `status` |
| `t3_thread_organize` | `pin`, `unpin`, `snooze` (needs `snoozedUntil`), `unsnooze`, `settle`, `unsettle`, `archive`, `unarchive`, `mark_unread`. Settling this thread applies at turn end |
| `t3_pending_request` | `list`, `read`, `respond` for pending user questions. Approvals aren't listed and can't be answered |
| `t3_queue` | Queued messages: `list`, `read` (up to 16,000 chars), `edit`, `cancel`, `reorder`, `promote_to_steer` |

## project (`project/tools.ts`, 7 tools)

| Tool | What it does |
|---|---|
| `t3_thread_launch` | One new top-level thread, bound to its workspace before the agent starts. `title` is required. `message` up to 120,000 chars, up to 8 `attachments`. `scratch: true` uses a new Scratch folder with no project |
| `t3_project_list` (RO) | Lists projects, 1 to 100 per page |
| `t3_project_read` (RO) | One project: workspace and saved scripts (the actions the setup runner uses) |
| `t3_project_create` | Registers a folder. No `workspaceRoot`: makes a git repo from `title` with a README, icon and first commit |
| `t3_project_update` | Updates one project's settings. Omitted fields stay |
| `t3_project_delete` | Deletes one project. Nonempty needs `force: true`. The folder on disk stays |
| `t3_project_clone` | Clones a repository into a new or empty `destinationPath`. Register it after with `t3_project_create` |

`workspaceStrategy` shapes (`OrchestrationV2ThreadLaunchWorkspaceStrategy` in `packages/contracts/src/orchestrationV2.ts`):

```json
{ "type": "root", "branch": "optional" }
{ "type": "existing_worktree", "worktreePath": "/abs/path", "branch": "optional" }
{ "type": "worktree", "baseRef": "origin/main", "branch": "optional", "startFromOrigin": true }
```

## worktree (`worktree/tools.ts`, 3 tools)

| Tool | What it does |
|---|---|
| `t3_worktree_status` (RO) | This thread's worktree: attached or not, path, branch, project root, and the `startFromOrigin` default |
| `t3_worktree_handoff` | Moves this thread into a new worktree on a new branch. Ends the live session |
| `t3_worktree_list` (RO) | Branch refs and checkout paths for a thread's workspace. Detached worktrees are left out |

## pullRequests (`pullRequests/tools.ts`, 9 tools)

A PR is named by `url`, or by `repository` plus `number` (optional `host`, default this project's host).

| Tool | What it does |
|---|---|
| `link_pull_request` | Links a PR to the thread. T3 shows its status and settles the thread on merge |
| `link_pull_requests` | Links several in one call. Bad URLs come back in `invalidUrls` |
| `unlink_pull_request` | Removes a link. Succeeds with `wasLinked=false` when it wasn't linked |
| `unlink_pull_requests` | Unlinks every PR whose last known state is in `states` |
| `list_thread_pull_requests` (RO) | Linked PRs with last known state and stack order, bottom to top |
| `watch_pull_request` | Watches an open PR, linking it first if needed. Hidden from subagents |
| `unwatch_pull_request` | Stops watching. The PR stays linked. Hidden from subagents |
| `write_pull_request_guides` | Starts review-guide runs for up to 20 PRs. Fails while guides are off |
| `read_pull_request_guide` (RO) | Reads a stored guide and run state. `stale` is true when the PR head moved |

## preview (`preview/tools.ts`, 12 tools) and previewControls (`previewControls/tools.ts`, 2 tools)

| Tool | What it does |
|---|---|
| `preview_status` (RO) | Tab state: owner, pending dialog, URL, title, loading, viewport. Lists this thread's tabs and login `profiles` |
| `preview_open` | Opens a preview tab. `url`, or `target` for a dev server. `open=false` keeps it in the background |
| `preview_navigate` | Navigates the tab. Exactly one of `url` and `target: {kind: "environment-port", port}` |
| `preview_resize` | `{mode: "fill"}`, `{mode: "freeform", width, height}` or `{mode: "preset", preset, orientation}`. CSS size only |
| `preview_set_appearance` | `prefers-color-scheme`: `dark`, `light`, or `system` to clear |
| `preview_snapshot` | Page state, elements, diagnostics. Text caps near 20 KB. `save=true` writes a PNG and returns `screenshotPath` |
| `preview_act` | click, type, hover, select, drag, upload, press, scroll. `timeoutMs` defaults to 15000 |
| `preview_evaluate` | Runs JavaScript in the page. Returns `{value}`, up to 64 KB |
| `preview_wait_for` | Waits until all given locator, selector, text and URL conditions match |
| `preview_dialog` | Accepts or dismisses the dialog `preview_status` reports |
| `preview_recording_start`, `preview_recording_stop` | Records the tab. Stop returns a local file path, max 50 MiB |
| `t3_preview_list` (RO) | This thread's preview tabs, with `runtime` |
| `t3_preview_close` | Closes one preview tab this thread owns |

You can read any listed tab, but only act on your own tab or an unclaimed one with no human in control.

## html (`html/tools.ts`, 2 tools)

| Tool | What it does |
|---|---|
| `html_preview` (RO) | Checks a page before rendering. Returns a PNG, `contentHeight` and console output. Width 240 to 1600 CSS px, theme `dark` (default) or `light` |
| `html_render` | Shows a finished page inline in the thread, above the final reply |

Both take inline HTML (max 512,000 chars) or an absolute `.html` path.

## device (`device/tools.ts`, 4 tools)

| Tool | What it does |
|---|---|
| `device_list` (RO) | iOS Simulators and Android Emulators on every device host, and what's open in this thread's Device panel |
| `device_open` | Opens one by `deviceId` and `hostId`, booting it if needed. Returns the `agent-device` CLI call pinned to it |
| `device_screenshot` (RO) | PNG of an open device's screen. Taps and text go through the `agent-device` CLI |
| `device_close` | Removes a device from the panel. `shutdown=true` also turns it off |

## attachment (`attachment/tools.ts`, 3 tools)

| Tool | What it does |
|---|---|
| `t3_attachment_prepare_upload` | Returns an upload URL. POST the file's exact bytes to `relativeUrl` on the MCP server's HTTP origin |
| `t3_attachment_discard` | Discards a pending upload, not a sent attachment |
| `t3_thread_send_attachments` | Sends uploaded attachments as a new message. No retry key |

## environment (`environment/tools.ts`, 2 tools)

| Tool | What it does |
|---|---|
| `t3_environment_read` (RO) | This server's identity and preferences |
| `t3_environment_preferences_update` | Updates environment-wide preferences. Needs a live full-access or default caller thread. `customInstructions: ""` clears it |

## toolSearch (`toolSearch/tools.ts`, 1 tool)

| Tool | What it does |
|---|---|
| `tool_search` (RO) | Loads T3 tools the session doesn't list yet, by name or purpose. Up to 10 results per query (`apps/server/src/mcp/McpToolExposure.ts`) |

## How the server is wired into each provider

From `docs/orchestration-v2/orchestrator-mcp-server.md`:

- Claude: an HTTP MCP server named `t3-code` with a bearer token, plus `mcp__t3-code__*` in `allowedTools`.
- Codex: registered twice. `t3-code` has every tool except `t3_thread_wait`, and `t3-code-direct` has only `t3_thread_wait` so a blocking wait is a direct tool call.
- Cursor, Grok and ACP Registry agents: the same endpoint through their `mcpServers` field.
- Pi: a T3-owned extension bridges to the HTTP endpoint and keeps the `mcp__t3-code__` names.

The token is scoped to the environment, the parent thread, the provider instance and the provider session. It's revoked when the session is released and isn't stored in orchestration state.
