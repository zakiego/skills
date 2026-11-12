# T3 MCP tools

T3 Code runs one authenticated MCP endpoint per server, `http://127.0.0.1:<port>/mcp`, and injects it into every provider session under the server key `t3-code` (`docs/orchestration-v2/orchestrator-mcp-server.md`). In Claude Code the tools show up as `mcp__t3-code__<name>`.

Facts below come from pingdotgg/t3code at commit `fc2b5de20cb572d2333e03284466e3c804d25c84`. Tool definitions live in `apps/server/src/mcp/toolkits/<area>/tools.ts`, input shapes in `packages/contracts/src/orchestratorMcp.ts`. The full per-tool list is in `mcp-tools-list.md`.

## Tools load late

Only four tools are listed up front for a client that defers tools: `orchestrator_capabilities`, `delegate_task`, `task_status` and `tool_search` (`DIRECT_TOOLS` in `apps/server/src/mcp/McpToolExposure.ts`). `request_secret` is also marked always-load for Claude Code (`toolkits/orchestrator/tools.ts`).

Everything else has to be loaded first. In Claude Code that means ToolSearch with `select:mcp__t3-code__<name>`. On other providers, T3's own `tool_search` takes a name or a purpose and returns up to 10 matches, which then stay listed for the session. Try the name once before you call a tool missing.

## Pick the tool

| Job | Tool |
|---|---|
| Run a subagent on another provider, model or checkout | `delegate_task` (see `delegation.md`) |
| Read what another thread said or did | `t3_thread_read` (`view: "activity"` for tool calls and requests) |
| Find a thread by text | `t3_thread_search`, or `t3_thread_list` for a project's newest threads |
| Talk to a thread | `t3_thread_send` (`mode`: `auto`, `queue`, `steer`, `restart`) |
| Block until a thread's run ends | `t3_thread_wait` |
| Stop a top-level thread's turn | `t3_thread_interrupt` (for a delegate use `task_cancel`) |
| One new top-level thread, optionally in its own worktree | `t3_thread_launch` with `workspaceStrategy` |
| Several new top-level threads in this checkout | `create_threads` (1 to 20) |
| Rename a thread or regenerate its title | `t3_thread_update` |
| Pin, snooze, settle, archive, mark unread | `t3_thread_organize` |
| Change a thread's provider, model or options | `t3_thread_configure` |
| Fork a thread or merge context back | `t3_thread_transfer` |
| Edit, reorder or cancel queued messages | `t3_queue` |
| Answer a pending question in a thread | `t3_pending_request` |
| Move this thread into a new worktree | `t3_worktree_status`, then `t3_worktree_handoff` |
| List branches and checkout paths | `t3_worktree_list` |
| Attach a PR to the thread | `link_pull_request`, `link_pull_requests` |
| Get woken on checks, reviews, conflicts | `watch_pull_request`, `unwatch_pull_request` |
| Projects | `t3_project_list`, `_read`, `_create`, `_update`, `_delete`, `_clone` |
| Ask the user for a token or password | `request_secret` |
| Recurring or webhook-triggered work | `schedule_task`, `list_scheduled_tasks`, `delete_scheduled_task`, `run_scheduled_task_now` |
| Show a chart or mockup inline | `html_preview`, then `html_render` |
| Drive a browser tab | `preview_*`, `t3_preview_list`, `t3_preview_close` |
| iOS Simulator or Android Emulator | `device_list`, `device_open`, `device_screenshot`, `device_close` |
| Work on another machine | `t3_environment_links`, `t3_environment_link`, then pass `environmentId` |
| Keep the thread in Working while a background command runs | `t3_background_wait` (Claude only) |

## Rules that apply across tools

- Mode ceiling. A tool that changes another thread needs the calling thread's live run, and the target's runtime and interaction modes can't be broader than the caller's. The same ceiling applies to child creation (Policy And Idempotency in `docs/orchestration-v2/orchestrator-mcp-server.md`).
- Scope. Thread tools accept any thread id in the environment. List and search cover one project: the caller's, unless `projectId` or `allProjects` is given.
- Retry keys. `clientRequestId` makes a call idempotent within the provider session: the same key returns the same durable work. A call without one creates new work each time. `t3_thread_send_attachments` has no retry key at all.
- Mention threads by `link`. Results carry `link` (`t3-thread://v2/<environmentId>/<threadId>`). Paste it verbatim in the reply. A title goes stale when the user renames the thread.
- Reads have side effects. `t3_thread_read` and `task_status` on a child's final result mark it delivered, which is why both are flagged not read-only.
- Keep reads small. `t3_thread_read` takes `limit` and `maxCharsPerItem`. Page with `afterPosition=nextPosition`. For cut-off text, pass `itemId` with `textOffset=nextTextOffset`.
- `omit threadId` means this thread for `t3_thread_update`, `t3_thread_organize`, `t3_thread_configure`, `t3_thread_transfer`, `t3_queue`, `t3_pending_request`, `t3_worktree_list` and the PR tools.

## Threads: the choices that matter

`t3_thread_send` modes (`toolkits/orchestrator/tools.ts`, doc section `t3_thread_send`):

- `auto`: starts an idle thread, steers a fully active turn, or queues behind a turn that can't be steered yet.
- `queue`: a separate follow-up run after the active work.
- `steer`: needs a steerable active turn.
- `restart`: interrupt and restart. On a provider that can only stop and queue, it stops the turn and puts the message at the front of the queue.

A send to a finished child thread starts a fresh task in that child and returns its `taskId`. It doesn't reopen the completed task or change its published result.

`t3_thread_launch` vs `create_threads`: launch makes one thread and binds its workspace before the agent starts. `workspaceStrategy` is `worktree` (new checkout from `baseRef`), `existing_worktree` (bind `worktreePath`) or `root` (the project checkout, which is the default and is not the caller's worktree). `create_threads` makes up to 20 threads that inherit the caller's project, branch and worktree path, with no subagent lineage. Neither is delegation. A worktree made in the shell or in the task prompt doesn't change the binding.

For `worktree`, honor a base the user asked for. Otherwise independent work starts from the default branch as `remote/branch` with `startFromOrigin: true`, and stacked or unpublished work uses its local base with `startFromOrigin: false`. Uncommitted edits aren't copied (`workspaceStrategy` annotation in `toolkits/project/tools.ts`).

`t3_thread_wait` returns when the run reaches `completed`, `failed`, `cancelled`, `interrupted` or `rolled_back`. No `runId` pins the latest run, and an idle thread returns at once. A timeout reports status and cancels nothing. Default wait is 10 minutes, capped at 60 (`DEFAULT_WAIT_TIMEOUT_MS`, `MAX_WAIT_TIMEOUT_MS` in `apps/server/src/mcp/OrchestratorMcpService.ts`).

`t3_pending_request` lists and answers questions (`user_input`). It can't approve a command, file change or permission request. Only the user does that.

## Worktrees

`t3_worktree_handoff` moves the calling thread into a new worktree on a new branch and runs the project's setup script by default (`toolkits/worktree/tools.ts`). The move ends the live session, so call it last in the turn. `continuationPrompt` resumes the work there on the next turn, and without it the thread waits. It fails if the thread already has a worktree, so check `t3_worktree_status` first. The worktree stays on disk after the thread is deleted (cleanup: `worktree-cleanup.md`).

## Pull requests

- `link_pull_request` shows the PR's status on the thread and settles the thread on merge. Use `link_pull_requests` for several, for example every layer of a stack. Non-PR URLs come back in `invalidUrls`.
- `watch_pull_request` links if needed, then wakes the thread on failed checks, passed required checks, new comments or reviews, or conflicts. End the turn after calling it. The watch stays on across wakes, so don't call it again on a wake. A wake isn't a merge decision.
- Watch and unwatch are hidden from subagent threads (`hiddenFromSubagents` in `apps/server/src/mcp/McpInvocationContext.ts`). A delegated child can link but never watch.
- `unlink_pull_requests` removes every link whose last known state is in `states`. PRs with no known state stay linked.
- `write_pull_request_guides` starts review-guide runs for up to 20 PRs. Each takes minutes in a temporary checkout. `read_pull_request_guide` never starts a run.

## Secrets

`request_secret` opens a card for one secret (`OrchestratorMcpRequestSecretInput`). `delivery: "secretRef"` (default) returns a one-use reference for a T3 tool that accepts one, such as a webhook signature in `schedule_task`. `delivery: "file"` returns an owner-only file to read inside a command, deleted after 24 hours. Default timeout is 10 minutes, max 60. Results: `saved`, `declined` (don't ask again), `cancelled`, `timed_out`. Never put a secret in a `delegate_task` prompt.

## Previews and renders

- `html_render` shows a finished page inline above the final reply. Check it with `html_preview` first and pass its `contentHeight` as `height`. Inline HTML is capped at 512,000 characters. Pages must be self-contained, though local images given as absolute paths are inlined (`toolkits/html/tools.ts`).
- `preview_open` takes `url` or, for a dev server, `target: {kind: "environment-port", port}`. Parallel subagents in one session each need `reuseExistingTab=false` and then their own `tabId`.
- `preview_snapshot` returns an accessibility tree. Target elements in `preview_act` with `locator='aria-ref=<ref>'`. Refs die on navigation or a new snapshot.
- `t3_preview_list` marks each tab's `runtime`. Only `runtime: "server"` tabs can be automated. Others live in the user's desktop app.
- Close a tab you opened with `t3_preview_close` when you're done.

## Typed failures

Expected denials come back as an `OrchestratorMcpFailure` with one of these codes: `capability_denied`, `parent_not_active`, `provider_unavailable`, `model_unavailable`, `runtime_mode_escalation_denied`, `interaction_mode_escalation_denied`, `task_not_found`, `task_not_cancellable`, `thread_not_found`, `run_not_found`, `thread_not_sendable`, `thread_not_interruptible`, `invalid_request`, `orchestration_error`.

`parent_not_active` means the call needs a live run in the calling thread. `thread_not_found` also covers a deleted thread. On `provider_unavailable` or `model_unavailable`, call `orchestrator_capabilities` again and report it. Don't switch provider on your own.
