#!/bin/bash
# git-session-start.sh — SessionStart hook
#
# Creates a new session branch (without switching) and takes an initial
# snapshot of the working tree. The session branch is maintained in parallel
# via git plumbing — the user's checked-out branch is never touched.
#
# Input:  stdin JSON from Claude Code (may contain session_id)
# Output: stderr debug messages only
# Exit:   always 0 (hooks must never break the session)

set -uo pipefail

# Guard: skip if not in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Load shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/git-session-lib.sh"

# Read session ID from stdin
claude_read_stdin_session_id

# Generate unique branch name
claude_gen_branch_name

echo "[claude-git] Starting session: $BRANCH_NAME (id: $SESSION_ID_SHORT)" >&2

# Create session branch from current HEAD — no checkout
git branch "$BRANCH_NAME" HEAD 2>/dev/null || {
    echo "[claude-git] Failed to create branch $BRANCH_NAME, aborting" >&2
    exit 0
}

# Write state file
STATE_FILE=$(claude_state_file)
claude_write_state "$STATE_FILE" "$BRANCH_NAME"

echo "[claude-git] State file: $STATE_FILE" >&2

# Initial snapshot of working tree
if claude_snapshot "$BRANCH_NAME" "WIP: session start — initial snapshot $(date -Iseconds)"; then
    claude_increment_checkpoint "$STATE_FILE" >/dev/null
    echo "[claude-git] Initial snapshot captured" >&2
else
    echo "[claude-git] Working tree clean at session start (no snapshot needed)" >&2
fi

exit 0
