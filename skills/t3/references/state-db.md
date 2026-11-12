# T3 state database reference

Database: `~/.t3/userdata/statev2.sqlite` (`dbPath` in `apps/server/src/config.ts`). Migrations live in `apps/server/src/persistence/Migrations/`.

Source commit read: `fc2b5de20cb572d2333e03284466e3c804d25c84`. Table and column names below were confirmed with `.schema` against a live 0.1.9 database on 2026-11-13. The schema is internal and can change in any release, so run `.schema <table>` again when a query fails.

## Opening it safely

```bash
DB="file:$HOME/.t3/userdata/statev2.sqlite?mode=ro"
sqlite3 -readonly -cmd ".timeout 3000" "$DB" ".tables"
sqlite3 -readonly "$DB" ".schema orchestration_v2_projection_threads"
```

Always the `file:...?mode=ro` URI plus `-readonly`. Never write, never run `VACUUM`, never copy over the live file. To experiment, copy the `.sqlite`, `-wal` and `-shm` files to `/tmp` and query the copy.

## Tables worth knowing

| Table | Holds |
|---|---|
| `orchestration_v2_projection_threads` | One row per thread, child and subagent threads included |
| `orchestration_v2_projection_runs` | One row per turn. `ordinal` orders them within a thread |
| `orchestration_v2_projection_runtime_requests` | Approvals and questions. `status = 'pending'` blocks a thread |
| `orchestration_v2_projection_subagents` | Delegated tasks and native subagents, parent `thread_id` to `child_thread_id` |
| `orchestration_v2_projection_provider_sessions` | Provider session per thread, with `status` and `model` |
| `orchestration_v2_projection_messages`, `_turn_items` | Conversation content. Prefer `t3_thread_read` for this |
| `orchestration_v2_events` | Event log. Pruned after about a day, can be empty |
| `projection_projects` | Projects: `workspace_root`, `scripts_json` (saved actions), `default_thread_env_mode` |
| `scheduled_tasks` | Scheduled tasks: `schedule_json`, `next_run_at`, `last_run_status`, `last_run_error` |
| `scheduled_task_webhook_deliveries` | Recent webhook requests per task |
| `auth_sessions`, `auth_pairing_links` | Auth state. Don't quote rows from these |

Tables named `projection_thread*` and `orchestration_events` without `v2` are from the older orchestration and are not the live source for threads.

## Thread row

Columns: `thread_id`, `project_id`, `title`, `provider_instance_id`, `runtime_mode`, `interaction_mode`, `created_at`, `updated_at`, `archived_at`, `deleted_at`, `payload_json`.

Useful `payload_json` keys: `branch`, `worktreePath`, `modelSelection`, `lineage.parentThreadId`, `lineage.relationshipToParent`, `settledAt`, `unsettledAt`, `snoozedUntil`, `pinnedAt`, `linkedPullRequest`, `pullRequests`, `createdBy`, `creationSource`.

Thread id shapes seen in practice:

- a bare UUID: a normal thread started by the user
- `mcp:launch:<hash>`: a thread started with `t3_thread_launch`
- `thread:delegated-task:...`: a `delegate_task` child
- `thread:provider:<driver>:native-thread:...`: a provider-native subagent (for example Claude's own Agent tool)

## Run statuses

`queued`, `preparing`, `starting`, `running`, `waiting` are active (the recovery index in the schema lists exactly these). `completed`, `failed`, `cancelled`, `interrupted`, `rolled_back` are terminal (`t3_thread_wait` in `docs/orchestration-v2/orchestrator-mcp-server.md`).

Runtime request `kind` values: `command`, `file-read`, `file-change`, `mcp-elicitation`, `permission` (approvals) and `user_input` (questions). Status: `pending`, `resolved`, `cancelled`.

## Queries

Everything running right now:

```sql
select r.status, r.requested_at, r.thread_id, t.title
from orchestration_v2_projection_runs r
left join orchestration_v2_projection_threads t on t.thread_id = r.thread_id
where r.status in ('queued','preparing','starting','running','waiting')
order by r.requested_at;
```

Threads blocked on a human:

```sql
select q.kind, q.created_at, q.thread_id, t.title
from orchestration_v2_projection_runtime_requests q
left join orchestration_v2_projection_threads t on t.thread_id = q.thread_id
where q.status = 'pending';
```

Which threads use a worktree:

```sql
select thread_id, title, archived_at, json_extract(payload_json, '$.settledAt') as settled_at
from orchestration_v2_projection_threads
where json_extract(payload_json, '$.worktreePath') = '/Users/<you>/.t3/worktrees/<repo>/<name>';
```

Children of a thread:

```sql
select status, origin, started_at, completed_at, child_thread_id
from orchestration_v2_projection_subagents
where thread_id = '<parent-thread-id>'
order by started_at desc;
```

`origin` is `app_owned` for a `delegate_task` child and `provider_native` for a provider's own subagent.

Recent failed runs:

```sql
select r.completed_at, r.thread_id, t.title
from orchestration_v2_projection_runs r
left join orchestration_v2_projection_threads t on t.thread_id = r.thread_id
where r.status = 'failed'
order by r.completed_at desc limit 20;
```

Scheduled tasks and their last result:

```sql
select task_id, title, enabled, json_extract(schedule_json, '$.type') as type,
       next_run_at, last_run_at, last_run_status, last_run_error, run_count, thread_mode
from scheduled_tasks order by updated_at desc;
```

Saved actions of a project (what T3 really runs, as opposed to `t3.json`):

```sql
select title, workspace_root, scripts_json from projection_projects where deleted_at is null;
```

Biggest tables, when the file is large (slow on a multi-GB database):

```sql
select name, sum(pgsize) / 1048576 as mb from dbstat group by name order by mb desc limit 15;
```

`dbstat` needs a sqlite3 build with that module. The macOS system sqlite3 has it. If it errors, use `t3 doctor --dry-run` for the reclaimable size.
