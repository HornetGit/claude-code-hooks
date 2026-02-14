#!/bin/bash
# git-session-lib.sh — shared functions for Claude session safety net
#
# Sourced by: git-session-start.sh, git-session-checkpoint.sh, git-session-end.sh
# Never executed directly.
#
# How it works:
#   Each Claude Code session gets a dedicated git branch (claude/session/YYYYMMDD-HHMM-XXXX)
#   maintained via git plumbing (write-tree, commit-tree, update-ref) — the user's
#   checked-out branch is NEVER switched. Snapshots capture the full working tree at
#   session start, before context compaction, and at session end.
#
# Provides:
#   claude_read_stdin_session_id  — parse session_id from hook stdin JSON
#   claude_gen_branch_name        — generate unique session branch name
#   claude_state_file             — return path to session state file
#   claude_write_state            — create state file
#   claude_read_state             — source state file
#   claude_find_latest_state      — find most recent state file for this repo
#   claude_snapshot               — snapshot working tree onto session branch (no switch)
#   claude_increment_checkpoint   — bump checkpoint counter in state file

CLAUDE_SESSIONS_DIR="${HOME}/.claude/sessions"

# ---------------------------------------------------------------------------
# Read session_id from stdin JSON (same pattern as session-end.sh)
# Sets: SESSION_ID, SESSION_ID_SHORT
# ---------------------------------------------------------------------------
claude_read_stdin_session_id() {
    local stdin_data
    stdin_data=$(cat 2>/dev/null || true)
    SESSION_ID=$(echo "$stdin_data" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4 || true)
    if [ -z "$SESSION_ID" ]; then
        SESSION_ID="${$}-$(date +%s)"
    fi
    SESSION_ID_SHORT="${SESSION_ID:0:8}"
}

# ---------------------------------------------------------------------------
# Generate unique branch name
# Sets: BRANCH_NAME
# ---------------------------------------------------------------------------
claude_gen_branch_name() {
    local date_part time_part id_part
    date_part=$(date +%Y%m%d)
    time_part=$(date +%H%M)
    id_part="${SESSION_ID_SHORT:0:4}"
    BRANCH_NAME="claude/session/${date_part}-${time_part}-${id_part}"

    # Handle collision (extremely unlikely, but safe)
    local suffix=0
    while git rev-parse --verify "refs/heads/$BRANCH_NAME" >/dev/null 2>&1; do
        suffix=$((suffix + 1))
        BRANCH_NAME="claude/session/${date_part}-${time_part}-${id_part}-${suffix}"
    done
}

# ---------------------------------------------------------------------------
# State file path for current session
# ---------------------------------------------------------------------------
claude_state_file() {
    echo "${CLAUDE_SESSIONS_DIR}/.git-state-${SESSION_ID_SHORT}"
}

# ---------------------------------------------------------------------------
# Write state file
# ---------------------------------------------------------------------------
claude_write_state() {
    local state_file="$1"
    local branch_name="$2"
    mkdir -p "$CLAUDE_SESSIONS_DIR"
    cat > "$state_file" <<EOF
SESSION_BRANCH=${branch_name}
SESSION_ID=${SESSION_ID}
REPO_DIR=$(pwd)
STARTED=$(date -Iseconds)
CHECKPOINT_COUNT=0
EOF
}

# ---------------------------------------------------------------------------
# Read (source) state file — sets SESSION_BRANCH, SESSION_ID, REPO_DIR, etc.
# Returns 1 if file not found
# ---------------------------------------------------------------------------
claude_read_state() {
    local state_file="$1"
    if [ -f "$state_file" ]; then
        # shellcheck disable=SC1090
        source "$state_file"
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Find most recent state file matching current repo
# ---------------------------------------------------------------------------
claude_find_latest_state() {
    local repo_dir
    repo_dir=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    # Find state files, check REPO_DIR matches, return most recent
    for f in $(ls -t "${CLAUDE_SESSIONS_DIR}"/.git-state-* 2>/dev/null); do
        if grep -q "REPO_DIR=${repo_dir}" "$f" 2>/dev/null; then
            echo "$f"
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Snapshot working tree onto session branch using git plumbing (NO switch)
#
# Args: SESSION_BRANCH COMMIT_MESSAGE
# Returns: 0 if snapshot created, 1 if no changes or error
# ---------------------------------------------------------------------------
claude_snapshot() {
    local session_branch="$1"
    local message="$2"
    local temp_index tree parent parent_tree commit

    # Verify session branch exists
    if ! git rev-parse --verify "refs/heads/$session_branch" >/dev/null 2>&1; then
        echo "[claude-git] Branch $session_branch not found, skipping" >&2
        return 1
    fi

    temp_index=$(mktemp "${TMPDIR:-/tmp}/claude-git-idx.XXXXXX")

    # Initialize temp index from HEAD, stage all working tree changes
    GIT_INDEX_FILE="$temp_index" git read-tree HEAD 2>/dev/null
    GIT_INDEX_FILE="$temp_index" git add -A 2>/dev/null

    # Write tree object
    tree=$(GIT_INDEX_FILE="$temp_index" git write-tree 2>/dev/null)

    # Clean up temp index (truncate, not rm — safe for concurrent use)
    : > "$temp_index"

    if [ -z "$tree" ]; then
        echo "[claude-git] Failed to write tree, skipping" >&2
        return 1
    fi

    # Get parent commit on session branch
    parent=$(git rev-parse "refs/heads/$session_branch" 2>/dev/null)

    # Skip if tree unchanged from parent
    parent_tree=$(git rev-parse "${parent}^{tree}" 2>/dev/null || true)
    if [ "$tree" = "$parent_tree" ]; then
        echo "[claude-git] No changes since last snapshot, skipping" >&2
        return 1
    fi

    # Create commit — try GPG-signed first, fall back to unsigned
    commit=$(echo "$message" | git commit-tree "$tree" -p "$parent" -S 2>/dev/null) || \
    commit=$(echo "$message" | git commit-tree "$tree" -p "$parent" 2>/dev/null) || {
        echo "[claude-git] Failed to create commit, skipping" >&2
        return 1
    }

    # Move session branch pointer
    git update-ref "refs/heads/$session_branch" "$commit" 2>/dev/null

    echo "[claude-git] Snapshot ${commit:0:8} on $session_branch" >&2
    return 0
}

# ---------------------------------------------------------------------------
# Increment checkpoint count in state file, echo new count
# ---------------------------------------------------------------------------
claude_increment_checkpoint() {
    local state_file="$1"
    local count
    count=$(grep -o 'CHECKPOINT_COUNT=[0-9]*' "$state_file" 2>/dev/null | cut -d= -f2)
    count=${count:-0}
    count=$((count + 1))
    sed -i "s/CHECKPOINT_COUNT=[0-9]*/CHECKPOINT_COUNT=$count/" "$state_file" 2>/dev/null
    echo "$count"
}
