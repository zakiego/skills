#!/bin/bash
# t3wt.sh: find and remove T3 worktrees that are provably safe to delete.
#
#   t3wt.sh scan [--include-unarchived] [--settled-ok]          report every worktree, change nothing
#   t3wt.sh remove [--include-unarchived] [--settled-ok] PATH…  re-check each PATH, remove only if SAFE
#
# A worktree is SAFE only when every check passes. Any failed or inconclusive
# check makes it KEEP. Removal uses `git worktree remove` without --force, keeps
# the branch, and logs a restore command to ~/.t3/worktree-cleanup.log.
#
# Written for macOS bash 3.2 (no associative arrays, no mapfile).

set -u

ROOT="$HOME/.t3/worktrees"
STATE_DB="$HOME/.t3/userdata/statev2.sqlite"
LOG="$HOME/.t3/worktree-cleanup.log"
RECENT_MIN=120          # any file touched in the last N minutes means KEEP
IDLE_HOURS=24           # --include-unarchived still needs threads idle this long

# Ignored paths that are pure build/install output and can always be regenerated.
REGEN_RE='(^|/)(node_modules|\.turbo|\.next|\.nuxt|\.output|\.svelte-kit|\.astro|\.wrangler|\.vercel|\.netlify|\.tanstack|\.vinxi|\.nitro|\.cache|\.parcel-cache|\.vite|dist|build|out|coverage|\.pnpm-store|__pycache__|\.pytest_cache|\.ruff_cache|\.mypy_cache|\.venv|target|\.vite-cache)(/|$)|(^|/)\.DS_Store$|\.tsbuildinfo$|\.log$|(^|/)\.wt\.json$|(^|/)\.impeccable/hook\.cache\.json$'

# Env files (.env, .env.local, .dev.vars...) pass only if every line already
# exists verbatim in the main checkout's copy, or is a local URL/port line
# (T3 gives each worktree its own port). Any extra secret means KEEP.
ENV_RE='(^|/)(\.env(\..+)?|\.dev\.vars(\..+)?)$'
LOCAL_LINE_RE='^[[:space:]]*(#.*)?$|localhost|127\.0\.0\.1|^[A-Z_]*PORT='

PER_WT_KEYS="${T3_PER_WORKTREE_KEYS:-$HOME/.config/t3-skill/per-worktree-keys.txt}"

env_covered() {  # env_covered WT_FILE MAIN_FILE REPO
  [ -f "$2" ] || return 1
  local line key
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s' "$line" | grep -Eq "$LOCAL_LINE_RE" && continue
    key=${line%%=*}; key=${key#export }
    if [ -f "$PER_WT_KEYS" ] && grep -Eq "^$3[[:space:]]+$key[[:space:]]*$" "$PER_WT_KEYS"; then
      continue   # regenerated per worktree by the repo's own setup
    fi
    grep -Fxq -- "$line" "$2" || return 1
  done < "$1"
  return 0
}

INCLUDE_UNARCHIVED=0
SETTLED_OK=0            # --settled-ok: a settled thread counts as closed, like archived
CWD_LIST=""

die() { echo "error: $*" >&2; exit 2; }

for bin in git gh jq sqlite3 lsof; do
  command -v "$bin" >/dev/null 2>&1 || die "$bin not found on this machine"
done
[ -d "$ROOT" ] || die "$ROOT not found on this machine"

load_cwds() {
  # Current working directory of every process, so we never pull a worktree
  # out from under a running shell, dev server, or agent.
  CWD_LIST=$(mktemp -t t3wt-cwd)
  lsof -nP -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' > "$CWD_LIST"
}

# check PATH -> prints "SAFE|KEEP<TAB>branch<TAB>sha<TAB>main<TAB>reasons"
check() {
  local wt="$1" reasons="" ok_merge=""
  local real main common gitdir br sha

  add() { reasons="${reasons:+$reasons; }$1"; }

  real=$(cd "$wt" 2>/dev/null && pwd -P) || { printf 'KEEP\t-\t-\t-\tpath missing\n'; return; }
  local rootreal; rootreal=$(cd "$ROOT" && pwd -P)
  case "$real" in
    "$rootreal"/*/*) ;;
    *) printf 'KEEP\t-\t-\t-\tnot under %s/<repo>/<name>\n' "$ROOT"; return ;;
  esac
  case "${real#$rootreal/}" in */*/*) printf 'KEEP\t-\t-\t-\tnested too deep\n'; return ;; esac

  # Must be a linked worktree (.git is a file), never a main checkout.
  [ -f "$real/.git" ] || { printf 'KEEP\t-\t-\t-\tnot a linked worktree (.git is not a file)\n'; return; }

  common=$(git -C "$real" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || { printf 'KEEP\t-\t-\t-\tgit cannot read it\n'; return; }
  gitdir=$(git -C "$real" rev-parse --path-format=absolute --git-dir 2>/dev/null)
  case "$common" in */.git) main=$(dirname "$common") ;; *) printf 'KEEP\t-\t-\t-\tbare or unusual repo layout\n'; return ;; esac
  [ -d "$main" ] || { printf 'KEEP\t-\t-\t-\tmain checkout %s missing\n' "$main"; return; }

  br=$(git -C "$real" symbolic-ref -q --short HEAD 2>/dev/null) || br=""
  sha=$(git -C "$real" rev-parse HEAD 2>/dev/null) || sha=""
  [ -n "$sha" ] || add "no HEAD commit"
  [ -n "$br" ] || add "detached HEAD"

  # Locked worktrees are locked on purpose.
  if git -C "$main" worktree list --porcelain 2>/dev/null | awk -v p="$real" '
      $1=="worktree"{cur=$2} $1=="locked" && cur==p {f=1} END{exit !f}'; then
    add "worktree is locked"
  fi

  # No half-finished git operation.
  local op
  for op in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG rebase-merge rebase-apply; do
    [ -e "$gitdir/$op" ] && add "git operation in progress ($op)"
  done

  # No staged, modified, deleted, or untracked files.
  local st
  st=$(git -C "$real" status --porcelain --untracked-files=all 2>&1) || add "git status failed"
  [ -n "$st" ] && add "uncommitted changes ($(printf '%s\n' "$st" | wc -l | tr -d ' ') paths)"

  # Ignored files: allowed only if regenerable, or an identical copy exists in
  # the main checkout (e.g. a .env that T3 copied in).
  local ign unique=""
  while IFS= read -r ign; do
    [ -z "$ign" ] && continue
    printf '%s' "$ign" | grep -Eq "$REGEN_RE" && continue
    local src="$real/${ign%/}" dst="$main/${ign%/}"
    if [ -d "$src" ]; then
      [ -d "$dst" ] && diff -rq "$src" "$dst" >/dev/null 2>&1 && continue
    else
      [ -f "$dst" ] && cmp -s "$src" "$dst" && continue
      if printf '%s' "$ign" | grep -Eq "$ENV_RE" && env_covered "$src" "$dst" "$(basename "$(dirname "$real")")"; then continue; fi
    fi
    unique="${unique:+$unique, }${ign%/}"
  done <<EOF
$(git -C "$real" ls-files --others --ignored --exclude-standard --directory 2>/dev/null)
EOF
  [ -n "$unique" ] && add "ignored files not in main checkout: $unique"

  # Merged: a merged PR whose head is exactly this commit, or the commit is
  # already contained in the remote default branch.
  if [ -n "$br" ] && [ -n "$sha" ]; then
    local prs
    if prs=$(cd "$real" && gh pr list --head "$br" --state merged --limit 20 --json number,headRefOid 2>/dev/null); then
      ok_merge=$(printf '%s' "$prs" | jq -r --arg s "$sha" '[.[] | select(.headRefOid==$s) | "#\(.number)"] | first // empty')
    else
      add "gh pr lookup failed"
    fi
    if [ -z "$ok_merge" ]; then
      local def
      def=$(git -C "$real" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null)
      for ref in $def origin/main origin/master; do
        if git -C "$real" rev-parse -q --verify "$ref" >/dev/null 2>&1 &&
           git -C "$real" merge-base --is-ancestor "$sha" "$ref" 2>/dev/null; then
          ok_merge="in $ref"; break
        fi
      done
    fi
    [ -z "$ok_merge" ] && add "not merged (no merged PR at this exact commit, not in origin default branch)"
  fi

  # Nothing running inside it.
  if grep -Fxq "$real" "$CWD_LIST" || grep -Fq "$real/" "$CWD_LIST"; then
    add "a process has its working directory inside"
  fi

  # Not touched recently. Tracked files are skipped: git status above is clean,
  # so they match HEAD byte for byte (a checkout or pnpm install bumps their
  # mtime without changing them). Anything else written recently means KEEP.
  local recent="" f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    printf '%s' "${f#$real/}" | grep -Eq "$REGEN_RE" && continue   # build output
    git -C "$real" ls-files --error-unmatch -- "${f#$real/}" >/dev/null 2>&1 && continue
    recent="$f"; break
  done <<EOF
$(find "$real" \( -name node_modules -o -name .git \) -prune -o -type f -mmin -"$RECENT_MIN" -print 2>/dev/null)
EOF
  [ -n "$recent" ] && add "untracked file modified in the last ${RECENT_MIN} min (${recent#$real/})"

  # T3 threads bound to this worktree must be archived or deleted.
  if [ -f "$STATE_DB" ]; then
    local row q open newest
    # Count open (not archived, not deleted) threads in SQL. Parsing rows in
    # bash with a tab IFS would collapse the empty archived/deleted columns.
    q="select count(*) || '|' || coalesce(max(updated_at),'')
       from orchestration_v2_projection_threads
       where archived_at is null and deleted_at is null
         and not ($SETTLED_OK = 1
                  and json_extract(payload_json,'\$.settledAt') is not null
                  and (json_extract(payload_json,'\$.unsettledAt') is null
                       or json_extract(payload_json,'\$.unsettledAt') < json_extract(payload_json,'\$.settledAt')))
         and json_extract(payload_json,'\$.worktreePath') in ('$(printf '%s' "$wt" | sed "s/'/''/g")','$(printf '%s' "$real" | sed "s/'/''/g")')"
    if row=$(sqlite3 -readonly "file:$STATE_DB?mode=ro" "$q" 2>/dev/null) && [ -n "$row" ]; then
      open=${row%%|*}; newest=${row#*|}
      if [ "$open" -gt 0 ]; then
        if [ "$INCLUDE_UNARCHIVED" -eq 1 ]; then
          local cutoff
          cutoff=$(date -u -v-"${IDLE_HOURS}"H +%Y-%m-%dT%H:%M:%S)
          [ "$newest" \> "$cutoff" ] && add "$open open T3 thread(s), active within ${IDLE_HOURS}h"
        else
          add "$open open T3 thread(s), archive them in T3 first"
        fi
      fi
    else
      add "cannot read T3 state db"
    fi
  else
    add "T3 state db not found"
  fi

  if [ -z "$reasons" ]; then
    printf 'SAFE\t%s\t%s\t%s\tmerged %s, clean\n' "$br" "$sha" "$main" "$ok_merge"
  else
    printf 'KEEP\t%s\t%s\t%s\t%s\n' "${br:--}" "${sha:--}" "$main" "$reasons"
  fi
}

cmd="${1:-}"; shift || true
while :; do
  case "${1:-}" in
    --include-unarchived) INCLUDE_UNARCHIVED=1; shift ;;
    --settled-ok) SETTLED_OK=1; shift ;;
    *) break ;;
  esac
done

case "$cmd" in
  scan)
    load_cwds
    safe_kb=0
    for wt in "$ROOT"/*/*/; do
      [ -d "$wt" ] || continue
      wt=${wt%/}
      res=$(check "$wt")
      verdict=$(printf '%s' "$res" | cut -f1)
      kb=$(du -sk "$wt" 2>/dev/null | cut -f1)
      [ "$verdict" = SAFE ] && safe_kb=$((safe_kb + kb))
      printf '%s\t%6sM\t%s\t%s\t%s\n' "$verdict" "$((kb / 1024))" "${wt#$ROOT/}" \
        "$(printf '%s' "$res" | cut -f2)" "$(printf '%s' "$res" | cut -f5)"
    done | sort
    echo "---"
    echo "Nothing was changed. Remove SAFE ones with: $0 remove <path>..."
    rm -f "$CWD_LIST"
    ;;
  remove)
    [ $# -gt 0 ] || die "usage: $0 remove [--include-unarchived] [--settled-ok] PATH..."
    load_cwds
    status=0
    for wt in "$@"; do
      wt=${wt%/}
      case "$wt" in /*) ;; *) wt="$ROOT/$wt" ;; esac
      res=$(check "$wt")
      IFS=$'\t' read -r verdict br sha main why <<EOF
$res
EOF
      if [ "$verdict" != SAFE ]; then
        echo "SKIP  ${wt#$ROOT/}: $why"
        status=1
        continue
      fi
      # No --force: git itself refuses if anything changed since the check.
      if git -C "$main" worktree remove "$wt" 2>/tmp/t3wt-err.$$; then
        printf '%s\tremoved\t%s\t%s\t%s\t%s\t%s\trestore: git -C %q worktree add %q %q\n' \
          "$(date '+%Y-%m-%d %H:%M:%S')" "$main" "$wt" "$br" "$sha" "$why" "$main" "$wt" "$br" >> "$LOG"
        echo "OK    ${wt#$ROOT/} ($br, $why)"
        rmdir "$(dirname "$wt")" 2>/dev/null || true   # only if the repo folder is now empty
      else
        echo "FAIL  ${wt#$ROOT/}: $(cat /tmp/t3wt-err.$$)"
        status=1
      fi
      rm -f /tmp/t3wt-err.$$
    done
    rm -f "$CWD_LIST"
    echo "Log: $LOG"
    exit $status
    ;;
  *)
    die "usage: $0 scan [--include-unarchived] [--settled-ok] | remove [--include-unarchived] [--settled-ok] PATH..."
    ;;
esac
