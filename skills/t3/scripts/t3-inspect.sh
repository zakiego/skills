#!/bin/bash
# Read-only snapshot of a T3 Code install. Never writes to the T3 home.
#
#   t3-inspect.sh status            server liveness, sizes, active runs, pending requests
#   t3-inspect.sh thread <id>       one thread: state, recent runs, pending requests, log paths
#   t3-inspect.sh find <text>       threads whose title or worktree path contains <text>
#                                   (provider-native subagent threads are left out)
#
# Paths follow deriveServerPaths in apps/server/src/config.ts (pingdotgg/t3code).
# Table and column names were checked against a 0.1.9 database. If T3 changes
# the schema, a query fails loudly instead of printing wrong data.
# Written for macOS bash 3.2. Needs sqlite3 and jq.

set -u

T3_HOME="${T3CODE_HOME:-$HOME/.t3}"
STATE="$T3_HOME/userdata"
DB="$STATE/statev2.sqlite"
LOGS="$STATE/logs"

die() { echo "error: $*" >&2; exit 1; }

command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 not found"
command -v jq >/dev/null 2>&1 || die "jq not found"
[ -d "$T3_HOME" ] || die "$T3_HOME not found on this machine"
[ -f "$DB" ] || die "$DB not found"

# Read-only URI: sqlite never takes a write lock on the live database.
q() { sqlite3 -readonly -cmd ".timeout 3000" "file:$DB?mode=ro" "$@"; }

# Single quotes are doubled so user text is always a SQL string literal.
sqlstr() { printf "%s" "$1" | sed "s/'/''/g"; }

size_of() { [ -e "$1" ] && du -sh "$1" 2>/dev/null | cut -f1 || echo "-"; }

cmd_status() {
  local rt="$STATE/server-runtime.json"
  echo "T3 home: $T3_HOME"
  if [ -f "$rt" ]; then
    local pid port ver started
    pid=$(jq -r '.pid // empty' "$rt")
    port=$(jq -r '.port // empty' "$rt")
    ver=$(jq -r '.serverVersion // "unknown"' "$rt")
    started=$(jq -r '.startedAt // "unknown"' "$rt")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "Server:  running, pid $pid, port $port, version $ver, started $started"
    else
      echo "Server:  NOT running (stale server-runtime.json: pid $pid, version $ver)"
    fi
  else
    echo "Server:  no server-runtime.json (server never started for this home, or it shut down cleanly)"
  fi

  echo
  echo "Sizes:"
  echo "  database   $(size_of "$DB")   (wal: $(size_of "$DB-wal"))"
  echo "  logs       $(size_of "$LOGS")"
  echo "  worktrees  $(size_of "$T3_HOME/worktrees")"
  echo "  disk free  $(df -h "$T3_HOME" | tail -1 | awk '{print $4}')"

  echo
  echo "Active runs (queued, preparing, starting, running, waiting):"
  q -header -list -separator "  |  " "
    select r.status, r.requested_at, r.provider, r.thread_id, substr(t.title, 1, 50) as title
    from orchestration_v2_projection_runs r
    left join orchestration_v2_projection_threads t on t.thread_id = r.thread_id
    where r.status in ('queued','preparing','starting','running','waiting')
    order by r.requested_at;" || die "cannot read runs (schema changed?)"

  echo
  echo "Pending requests (a thread blocked on an approval or a question):"
  q -header -list -separator "  |  " "
    select q.kind, q.created_at, q.thread_id, substr(t.title, 1, 50) as title
    from orchestration_v2_projection_runtime_requests q
    left join orchestration_v2_projection_threads t on t.thread_id = q.thread_id
    where q.status = 'pending'
    order by q.created_at;" || die "cannot read runtime requests (schema changed?)"

  echo
  echo "Running delegated tasks and subagents:"
  q -header -list -separator "  |  " "
    select status, origin, started_at, thread_id as parent_thread, child_thread_id
    from orchestration_v2_projection_subagents
    where status not in ('completed','failed','cancelled','interrupted')
    order by started_at;" || die "cannot read subagents (schema changed?)"

  if [ -f "$LOGS/event-loop-stalls.ndjson" ]; then
    echo
    echo "Last event loop stalls (server froze for more than 2 s):"
    tail -3 "$LOGS/event-loop-stalls.ndjson" | jq -r '"  \(.time)  \(.delayMaxMs) ms, rss \(.rssMb) MB"' 2>/dev/null
  fi
}

cmd_thread() {
  [ $# -ge 1 ] || die "usage: t3-inspect.sh thread <thread-id>"
  local id; id=$(sqlstr "$1")
  local found; found=$(q "select count(*) from orchestration_v2_projection_threads where thread_id = '$id';")
  [ "$found" = "1" ] || die "no thread with id $1 (try: t3-inspect.sh find <text>)"

  echo "Thread:"
  q -line "
    select thread_id, title, project_id, provider_instance_id,
      json_extract(payload_json, '\$.modelSelection.model') as model,
      runtime_mode, interaction_mode,
      json_extract(payload_json, '\$.branch') as branch,
      json_extract(payload_json, '\$.worktreePath') as worktree_path,
      json_extract(payload_json, '\$.lineage.parentThreadId') as parent_thread,
      created_at, updated_at,
      json_extract(payload_json, '\$.settledAt') as settled_at,
      archived_at, deleted_at
    from orchestration_v2_projection_threads where thread_id = '$id';"

  echo
  echo "Last 8 runs (newest first):"
  q -header -list -separator "  |  " "
    select ordinal, status, requested_at, completed_at, run_id
    from orchestration_v2_projection_runs where thread_id = '$id'
    order by ordinal desc limit 8;"

  echo
  echo "Pending requests:"
  q -header -list -separator "  |  " "
    select kind, status, created_at, runtime_request_id
    from orchestration_v2_projection_runtime_requests
    where thread_id = '$id' and status = 'pending';"

  echo
  echo "Delegated tasks and subagents started by this thread:"
  q -header -list -separator "  |  " "
    select status, origin, started_at, completed_at, child_thread_id
    from orchestration_v2_projection_subagents where thread_id = '$id'
    order by started_at desc limit 10;"

  echo
  local plog="$LOGS/provider/events.$1.log"
  if [ -f "$plog" ]; then
    echo "Provider event log: $plog ($(size_of "$plog"))"
  else
    echo "Provider event log: none at $plog"
  fi
  local wt; wt=$(q "select json_extract(payload_json, '\$.worktreePath') from orchestration_v2_projection_threads where thread_id = '$id';")
  if [ -n "$wt" ]; then
    if [ -d "$wt" ]; then echo "Worktree: $wt (exists)"; else echo "Worktree: $wt (MISSING on disk)"; fi
  fi
}

cmd_find() {
  [ $# -ge 1 ] || die "usage: t3-inspect.sh find <text>"
  local text; text=$(sqlstr "$1")
  q -header -list -separator "  |  " "
    select thread_id, updated_at, substr(title, 1, 60) as title,
      json_extract(payload_json, '\$.worktreePath') as worktree_path
    from orchestration_v2_projection_threads
    where deleted_at is null
      and thread_id not like 'thread:provider:%'
      and (title like '%$text%' or json_extract(payload_json, '\$.worktreePath') like '%$text%')
    order by updated_at desc limit 20;"
}

case "${1:-status}" in
  status) cmd_status ;;
  thread) shift; cmd_thread "$@" ;;
  find) shift; cmd_find "$@" ;;
  *) die "unknown command: $1 (use status, thread <id>, or find <text>)" ;;
esac
