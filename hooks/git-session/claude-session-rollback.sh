#!/bin/bash
# claude-session-rollback.sh — Helper for Claude session branch operations
#
# Usage:
#   claude-session-rollback.sh --list                          List all session branches
#   claude-session-rollback.sh --show <branch>                 Show checkpoint log for a branch
#   claude-session-rollback.sh --diff <branch> [checkpoint]    Show files changed (default: latest vs start)
#   claude-session-rollback.sh --restore <branch> <path>       Restore file(s) from latest snapshot
#   claude-session-rollback.sh --restore <branch>:<commit> <path>  Restore from specific checkpoint
#   claude-session-rollback.sh --cleanup [days]                List stale branches (default: 7 days)
#   claude-session-rollback.sh --trace <path>                  Find all versions of a file across session branches
#
# Examples:
#   claude-session-rollback.sh --list
#   claude-session-rollback.sh --show claude/session/20260214-1339-9061
#   claude-session-rollback.sh --diff claude/session/20260214-1339-9061
#   claude-session-rollback.sh --restore claude/session/20260214-1339-9061 PROJECTS/sandbox/file.txt
#   claude-session-rollback.sh --restore claude/session/20260214-1339-9061 .   # restore ALL files
#   claude-session-rollback.sh --cleanup 7
#   claude-session-rollback.sh --trace PROJECTS/sandbox/workflow-ast/test_file.txt

set -uo pipefail

# Guard: must be in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || { echo "Error: not in a git repository" >&2; exit 1; }

BRANCH_PREFIX="claude/session/"

# ── Helpers ───────────────────────────────────────────────────────

usage() {
    sed -n '3,20p' "$0" | sed 's/^# //;s/^#$//'
    exit 0
}

error() { echo "Error: $1" >&2; exit 1; }

validate_branch() {
    local branch="$1"
    git rev-parse --verify "refs/heads/$branch" >/dev/null 2>&1 || \
        error "Branch '$branch' not found. Use --list to see available branches."
}

# Count commits on session branch (above the fork point)
count_checkpoints() {
    local branch="$1"
    local fork_point
    fork_point=$(git merge-base HEAD "$branch" 2>/dev/null || echo "")
    if [ -n "$fork_point" ]; then
        git rev-list --count "$fork_point".."$branch" 2>/dev/null || echo "?"
    else
        git rev-list --count "$branch" 2>/dev/null || echo "?"
    fi
}

# ── Commands ──────────────────────────────────────────────────────

cmd_list() {
    local branches
    branches=$(git branch --list "${BRANCH_PREFIX}*" --format='%(refname:short)' 2>/dev/null)

    if [ -z "$branches" ]; then
        echo "No Claude session branches found."
        return 0
    fi

    echo "Claude session branches:"
    echo ""
    printf "  %-45s  %s  %s\n" "BRANCH" "CHECKPOINTS" "LAST ACTIVITY"
    printf "  %-45s  %s  %s\n" "------" "-----------" "-------------"

    while IFS= read -r branch; do
        local checkpoints last_date
        checkpoints=$(count_checkpoints "$branch")
        last_date=$(git log -1 --format='%ci' "$branch" 2>/dev/null | cut -d' ' -f1,2 | cut -c1-16)
        printf "  %-45s  %-11s  %s\n" "$branch" "$checkpoints" "$last_date"
    done <<< "$branches"
    echo ""
}

cmd_show() {
    local branch="$1"
    validate_branch "$branch"

    echo "Session branch: $branch"
    echo ""
    echo "Checkpoint log:"
    git log --oneline --format='  %h  %ci  %s' "$branch" --not --exclude="$branch" --branches="${BRANCH_PREFIX}*" --remotes 2>/dev/null | \
        git log --oneline --format='  %h  %ci  %s' "$branch" 2>/dev/null | head -20

    echo ""

    # Show state file if available
    local session_id="${branch##*-}"
    local state_files
    state_files=$(ls ~/.claude/sessions/.git-state-*"${session_id}"* 2>/dev/null || true)
    if [ -n "$state_files" ]; then
        echo "State file:"
        for f in $state_files; do
            [ -s "$f" ] && sed 's/^/  /' "$f"
        done
    fi
}

cmd_diff() {
    local branch="$1"
    local checkpoint="${2:-}"
    validate_branch "$branch"

    local from to
    to="$branch"

    if [ -n "$checkpoint" ]; then
        # Diff between specific checkpoint and latest
        from="${branch}~${checkpoint}"
    else
        # Diff between first commit (start) and latest (end)
        local fork_point
        fork_point=$(git merge-base HEAD "$branch" 2>/dev/null || echo "")
        if [ -n "$fork_point" ]; then
            from="$fork_point"
        else
            # Fallback: diff first vs last commit on branch
            local first_commit
            first_commit=$(git rev-list --reverse "$branch" 2>/dev/null | head -1)
            from="$first_commit"
        fi
    fi

    echo "Changes: $from -> $to"
    echo ""
    git diff-tree -r --name-status "$from" "$to" 2>/dev/null
}

cmd_restore() {
    local spec="$1"
    local path="$2"

    local branch commit
    if [[ "$spec" == *":"* ]]; then
        branch="${spec%%:*}"
        commit="${spec##*:}"
    else
        branch="$spec"
        commit=""
    fi

    validate_branch "$branch"

    local source
    if [ -n "$commit" ]; then
        source="$commit"
    else
        source="$branch"
    fi

    # Verify the source commit exists
    git rev-parse --verify "$source" >/dev/null 2>&1 || \
        error "Commit '$source' not found on branch '$branch'."

    # Check if path exists in the source
    if [ "$path" != "." ]; then
        git ls-tree "$source" -- "$path" >/dev/null 2>&1 || \
            error "Path '$path' not found in snapshot '$source'. Use --diff to see available files."
    fi

    echo "Restoring from: $source"
    echo "Path: $path"
    echo ""

    git checkout "$source" -- "$path" 2>&1
    local rc=$?

    if [ $rc -eq 0 ]; then
        echo "Restored successfully."
        if [ "$path" != "." ]; then
            echo "  $(ls -la "$path" 2>/dev/null || echo "$path")"
        else
            echo "  (all files restored from snapshot)"
        fi
    else
        error "Restore failed (exit code $rc)."
    fi
}

cmd_cleanup() {
    local days="${1:-7}"
    local cutoff
    cutoff=$(date -d "${days} days ago" +%s 2>/dev/null || date -v-"${days}"d +%s 2>/dev/null || echo "")

    if [ -z "$cutoff" ]; then
        error "Could not compute cutoff date for '${days} days ago'."
    fi

    echo "Session branches older than ${days} day(s):"
    echo ""

    local found=0
    for branch in $(git branch --list "${BRANCH_PREFIX}*" --format='%(refname:short)' 2>/dev/null); do
        local last_epoch
        last_epoch=$(git log -1 --format='%ct' "$branch" 2>/dev/null || echo "0")
        [ -z "$last_epoch" ] && last_epoch=0
        if [ "$last_epoch" -lt "$cutoff" ]; then
            local last_date
            last_date=$(git log -1 --format='%ci' "$branch" 2>/dev/null | cut -c1-16)
            echo "  $branch  (last: $last_date)"
            found=$((found + 1))
        fi
    done

    if [ "$found" -eq 0 ]; then
        echo "  (none found)"
    else
        echo ""
        echo "To delete: git branch -D <branch>"
        echo "To delete all: git branch --list '${BRANCH_PREFIX}*' | xargs git branch -D"
    fi
}

cmd_trace() {
    local path="$1"

    # Current file state
    local current_hash="(missing)" current_size="n/a"
    if [ -f "$path" ]; then
        current_hash=$(git hash-object "$path" 2>/dev/null || echo "(unhashable)")
        current_size=$(wc -c < "$path" 2>/dev/null | tr -d ' ')
    fi

    echo "Trace: $path"
    echo "Current: hash=${current_hash:0:12}  size=${current_size}"
    echo ""

    local branches
    branches=$(git branch --list "${BRANCH_PREFIX}*" --format='%(refname:short)' 2>/dev/null)

    if [ -z "$branches" ]; then
        echo "No session branches found."
        return 0
    fi

    printf "  %-8s  %-40s  %-8s  %-6s  %-16s  %s\n" \
           "COMMIT" "BRANCH" "STATUS" "SIZE" "DATE" "MESSAGE"
    printf "  %-8s  %-40s  %-8s  %-6s  %-16s  %s\n" \
           "------" "------" "------" "----" "----" "-------"

    local total_found=0

    while IFS= read -r branch; do
        # Walk commits on session branch above the fork point
        local fork_point commits
        fork_point=$(git merge-base HEAD "$branch" 2>/dev/null || echo "")

        if [ -n "$fork_point" ]; then
            commits=$(git rev-list "$fork_point".."$branch" 2>/dev/null)
        else
            commits=$(git rev-list "$branch" 2>/dev/null | head -30)
        fi

        [ -z "$commits" ] && continue

        for commit in $commits; do
            local blob_hash="" file_status="" blob_size="" date_str="" msg=""

            # Check if the file exists in this commit's tree
            blob_hash=$(git rev-parse "$commit:$path" 2>/dev/null || echo "")

            if [ -z "$blob_hash" ]; then
                continue  # file not in this snapshot — skip
            fi

            # Size of the blob
            blob_size=$(git cat-file -s "$blob_hash" 2>/dev/null || echo "?")

            # Compare to current working tree version
            if [ "$current_hash" = "(missing)" ]; then
                file_status="RESTORE"
            elif [ "$blob_hash" = "$current_hash" ]; then
                file_status="same"
            else
                file_status="DIFFERS"
            fi

            date_str=$(git log -1 --format='%ci' "$commit" 2>/dev/null | cut -c1-16)
            msg=$(git log -1 --format='%s' "$commit" 2>/dev/null | cut -c1-40)

            printf "  %-8s  %-40s  %-8s  %-6s  %-16s  %s\n" \
                   "${commit:0:8}" "$branch" "$file_status" "$blob_size" "$date_str" "$msg"
            total_found=$((total_found + 1))
        done
    done <<< "$branches"

    echo ""
    if [ "$total_found" -eq 0 ]; then
        echo "File not found in any session snapshot."
    else
        echo "Found $total_found snapshot(s). Rows marked DIFFERS contain a version different from current."
        echo "Use: --restore <branch>:<commit> $path"
    fi
}

# ── Main dispatch ─────────────────────────────────────────────────

case "${1:-}" in
    --list|-l)
        cmd_list
        ;;
    --show|-s)
        [ -z "${2:-}" ] && error "Usage: $0 --show <branch>"
        cmd_show "$2"
        ;;
    --diff|-d)
        [ -z "${2:-}" ] && error "Usage: $0 --diff <branch> [checkpoint]"
        cmd_diff "$2" "${3:-}"
        ;;
    --restore|-r)
        [ -z "${2:-}" ] && error "Usage: $0 --restore <branch>[:<commit>] <path>"
        [ -z "${3:-}" ] && error "Usage: $0 --restore <branch>[:<commit>] <path>"
        cmd_restore "$2" "$3"
        ;;
    --cleanup|-c)
        cmd_cleanup "${2:-7}"
        ;;
    --trace|-t)
        [ -z "${2:-}" ] && error "Usage: $0 --trace <path>"
        cmd_trace "$2"
        ;;
    --help|-h|"")
        usage
        ;;
    *)
        error "Unknown command: $1. Use --help for usage."
        ;;
esac
