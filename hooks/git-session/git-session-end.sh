#!/bin/bash
# git-session-end.sh — Stop hook
#
# Takes a final snapshot of the working tree onto the session branch
# and prints a summary. Uses git plumbing — no branch switch.
#
# Input:  stdin JSON from Claude Code (contains session_id)
# Output: stdout summary (visible to user), stderr debug messages
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

# Find state file for this session
STATE_FILE=$(claude_state_file)
if ! claude_read_state "$STATE_FILE"; then
    # Try finding latest state file as fallback
    STATE_FILE=$(claude_find_latest_state) || {
        echo "[claude-git] No session state found, skipping end hook" >&2
        exit 0
    }
    claude_read_state "$STATE_FILE" || {
        echo "[claude-git] Failed to read state file, skipping end hook" >&2
        exit 0
    }
fi

echo "[claude-git] Ending session: $SESSION_BRANCH" >&2

# Final snapshot
CHECKPOINT_NUM=$(claude_increment_checkpoint "$STATE_FILE")
if claude_snapshot "$SESSION_BRANCH" "WIP: session end — final snapshot $(date -Iseconds)"; then
    echo "[claude-git] Final snapshot #${CHECKPOINT_NUM} captured" >&2
fi

# Count total commits on session branch (since it diverged from its parent)
TOTAL_COMMITS=$(git rev-list --count HEAD.."$SESSION_BRANCH" 2>/dev/null || echo "0")

# Print user-facing summary to stdout
if [ "$TOTAL_COMMITS" -gt 0 ]; then
    echo ""
    echo "Claude session archived: $SESSION_BRANCH"
    echo "Checkpoints: ${TOTAL_COMMITS} snapshot(s) captured"
    echo "Claude can rollback to any checkpoint on request."
    echo ""
fi

exit 0
