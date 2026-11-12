# Delegation and scheduled tasks

A delegated task is a T3-owned child thread with its own run. The child gets only the `task` text (plus an optional `role`). Parent history isn't copied (`docs/orchestration-v2/orchestrator-mcp-server.md`).

Facts below come from pingdotgg/t3code at commit `fc2b5de20cb572d2333e03284466e3c804d25c84`. Input and result shapes are in `packages/contracts/src/orchestratorMcp.ts`, the service is `apps/server/src/mcp/OrchestratorMcpService.ts`. For the other T3 tools, see `mcp-tools.md`.

## When to use it

Use the provider's native subagent tool when the child runs on the same provider, a model it offers, and the same settings. Use `delegate_task` when the child needs another provider's model, settings the user asked for, or its own checkout. A new top-level thread (`t3_thread_launch`, `create_threads`) isn't delegation and is only for when the user asks for a new thread.

Delegation needs an active run in the calling thread, owned by the session's MCP credential. Without one the call fails with `parent_not_active`.

## Step 1: capabilities

Call `orchestrator_capabilities` once per thread before the first `delegate_task`. Call it again only after an error or when the user names a different provider. It returns:

- `inheritedProviderInstanceId`, `inheritedModel`, `inheritedOptions`: what a child gets when `target` is omitted.
- `runtimeMode`, `interactionMode`: the parent's modes, which are the child's ceiling.
- `providers[]`: `providerInstanceId`, `driverKind`, `models[]` (each with `options[]`: `id`, `values`, `default`), `canRunChildTask`, `canRunCrossProviderChildTask`, `constraints[]`, and sometimes `runtimeModes` and `omittedModels`.

The model list is short on purpose. Each provider lists custom, favorite and the caller's own models, plus all current models for Codex, Claude, Muse and Grok, or the first 8 current models for other providers. `omittedModels` counts the rest and `search` finds them, legacy ones included. `delegate_task` accepts any catalog model, listed or not.

A provider with `canRunChildTask: false` explains why in `constraints` (disabled, missing executable, missing authentication, no V2 adapter). Report it to the user. Don't pick another provider yourself.

## Step 2: delegate_task

```json
{
  "task": "Self-contained brief. The child sees nothing else.",
  "target": {
    "providerInstanceId": "from capabilities",
    "model": "model id",
    "options": { "effort": "max" }
  },
  "title": "Short label",
  "role": "review",
  "isolation": "worktree",
  "mode": "async",
  "clientRequestId": "stable-per-round"
}
```

Fields (`OrchestratorMcpDelegateTaskInput`):

| Field | Notes |
|---|---|
| `task` | Required. No secrets in it |
| `target.providerInstanceId` | Honored exactly. Fails when unavailable |
| `target.driverKind` | Looser: inherits the parent's instance if it can run child tasks, else picks an available instance of that driver. Prefer `providerInstanceId` |
| `target.model` | A different provider with no model uses that provider's first advertised model |
| `target.options` | A record like `{"effort": "max"}` or an array of `{id, value}`. Given values override inherited ones. `[]` or `{}` clears them |
| `target.environmentId`, `target.projectId` | Run on a linked machine. Default project: the one with this project's repository |
| `role` | `implementation`, `research`, `review`, `design`, `test`, `general` |
| `isolation` | `shared` (default) or `worktree` |
| `mode` | `async` (default) or `wait` |
| `timeoutMs` | `wait` only. Default 4 minutes, max 60 |
| `runtimeMode` | `inherit`, `approval-required`, `auto-accept-edits`, `auto`, `full-access`. Omit unless the user asks for a supervised child |
| `interactionMode` | `inherit`, `plan`, `default` |

## Modes

Runtime modes, narrowest first: `approval-required` (Supervised), `auto-accept-edits`, `auto`, `full-access` (`runtimeModeRank` in `apps/server/src/mcp/delegatedTaskModes.ts`, names in `docs/user/permission-modes.md`). Interaction modes: `plan`, then `default`.

- A child can match or narrow the parent's mode, never widen it. A broader request fails with `runtime_mode_escalation_denied` or `interaction_mode_escalation_denied`.
- A narrow runtime mode isn't read-only. It makes the child stop and wait for a human to approve each action, and child approvals show up in the parent conversation.
- When capabilities lists `runtimeModes` for a provider, it only offers those. An explicit mode outside the list is refused (`invalid_request`). An inherited mode steps down to the broadest one the provider offers. For example Muse and Kiro offer only Supervised and Full access, and Grok has no Auto-accept edits.

## Isolation

- `shared`: the child works in the parent's checkout. Fine for research and review, risky for two writers.
- `worktree`: T3 resolves the parent checkout's `HEAD` and launches the child in a new prepared worktree from that commit, with `startFromOrigin: false`. Uncommitted edits stay out, so commit what the child needs first. Use it for a separate checkout or a PR per child.

`worktree` fails with `invalid_request` when the parent's worktree is in a different repository from the project root, for example a git folder inside Scratch. Use `shared` there. Never create the child's checkout in the shell or describe it in `task`: that doesn't bind the thread to it.

## Lifecycle

`status`: `queued`, `running`, `waiting`, `completed`, `failed`, `cancelled`, `interrupted`.
`workState`: `working`, `waiting_for_children` (turn finished, its own delegates or background work still live), `result_available`.

1. `async` returns at once with `taskId`, `childThreadId` and `link`. When the result carries `next`, follow it: completion wakes the parent thread, so end the turn. Don't poll with `task_status`, `sleep` or a watcher.
2. `wait` blocks until the result, a timeout, a blocking question, or a pending approval. A timeout sets `waitTimedOut: true` and doesn't cancel the child.
3. `hasPendingQuestion: true`: the child is blocked on a question. Answer it with `t3_pending_request` on `childThreadId` (`list`, `read`, `respond`), or ask the user. The child's completion still wakes the parent.
4. `pendingApproval` names an open approval. It grants no approval rights. Only the user approves.
5. `summary` is the final result, taken from the latest assistant content of the final work turn. A failed run exposes its provider error first. Reading it through `task_status` or `t3_thread_read` marks it delivered.

A task stays nonterminal until its known work finishes. `hasPendingChildRuns` and `latestTerminal*` describe later turns in the child without replacing the published result.

Outside a wait, a child's question reaches the parent as a notification message. It steers into a running parent turn when the provider can steer without interrupting tools, else it queues. Approvals aren't routed this way.

## Follow-ups, reviews, cancel

- A new review round or re-check is a new `delegate_task` with the original brief, prior findings and open objections, and its own `clientRequestId`. Reuse a `clientRequestId` only to retry the same round: it returns the same durable work.
- A follow-up that needs the same child's memory goes through `t3_thread_send` on `childThreadId`. After the original task completed, that runs as a fresh task in the child and returns a new `taskId`.
- `task_cancel` stops the child's own delegates, then the child thread, cancels the task's queued turn and ends its PR watches. A finished task keeps its result. Result `status` is `cancel_requested` or a terminal status. Use it for a delegate you replace or no longer need. `t3_thread_interrupt` on a `childThreadId` is the wrong tool.
- A child whose brief says to watch a PR can't: watch tools are hidden from subagents. It links the PR and reports back.

## Provider notes

Any provider instance with a V2 orchestration adapter can run child tasks: Codex, Claude Agent SDK, Cursor Agent SDK, Grok, ACP Registry agents, OpenCode, OpenCode 2, Pi and Antigravity are named in the doc (Provider Support section). A provider turned off for a project can't start new turns there, including follow-ups from delegated tasks, though a delegate's result still lands in the parent (`docs/user/project-settings.md`).

## Scheduled tasks

`schedule_task` creates work that runs with no turn active. It needs `prompt` and `schedule`. With `scheduledTaskId` it updates that task and only the given fields change. When asked only to schedule, don't also run the prompt now.

`schedule` is an object (`packages/contracts/src/scheduledTask.ts`):

```json
{ "type": "interval", "everyMs": 3600000 }
{ "type": "fixed_time", "timeOfDay": "09:30", "weekdays": [1, 2, 3, 4, 5] }
{ "type": "once", "runAt": "2026-11-20T09:00:00+08:00" }
{ "type": "webhook" }
```

- `interval`: `everyMs` minimum 60000.
- `fixed_time`: `HH:MM` in the server's local time zone. `weekdays` 0 (Sunday) to 6 (Saturday), default every day.
- `once`: ISO date and time with an offset.
- `webhook`: runs on each qualifying request. Details in `scheduled-tasks.md`.

Other fields (`OrchestratorMcpScheduleTaskInput`):

| Field | Notes |
|---|---|
| `bindToCurrentThread` | Runs post into this thread. Unset: `true` when the caller's thread is in the task's project, else `false`. Unbound runs each launch a fresh thread |
| `freshSession` | Runs share one thread but each starts a fresh session with no memory of earlier runs |
| `enabled` | Default `true`. `false` pauses the task |
| `projectId` | Default: the caller's project. Required outside a thread |

The result has `nextRunAt`, `lastRunStatus` and, for webhooks, `webhookUrl`. Report the next run time or the URL to the user. `blockedByPolicy` means an admin policy stops the task.

Managing them: `list_scheduled_tasks` (don't call it from inside a scheduled run to find your own task, just do the prompt), `run_scheduled_task_now` (needs a full-access or default caller, and success means started), `delete_scheduled_task` (permanent, so pause with `enabled: false` when unsure). Deleting a thread also deletes tasks bound to it (`docs/user/project-settings.md`).

## Common failures

| Code | Meaning and fix |
|---|---|
| `parent_not_active` | No live run in the calling thread. Delegate from inside a turn |
| `provider_unavailable`, `model_unavailable` | Re-run `orchestrator_capabilities`, read `constraints`, tell the user |
| `runtime_mode_escalation_denied` | Asked for a broader mode than the parent's. Drop `runtimeMode` |
| `invalid_request` | Often a runtime mode the provider doesn't offer, or `worktree` isolation across repositories |
| `task_not_cancellable` | Nonterminal task with nothing to interrupt and no queued turn of its own |
| `task_not_found` | The `taskId` belongs to another parent thread |

When a delegate never comes back, check it from disk with `troubleshoot.md` (step 4 of its stuck-thread list).
