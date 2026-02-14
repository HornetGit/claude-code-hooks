#!/bin/bash
# git-session-checkpoint.sh — PreCompact hook
#
# Takes a checkpoint snapshot of the working tree onto the active session
# branch before context compaction. Uses git plumbing — no branch switch.
#
# Input:  stdin JSON from Claude Code (may or may not contain session_id)
# Output: stderr debug messages only
# Exit:   always 0 (hooks must never break the session)

set -uo pipefail

# Guard: skip if not in a git repo
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Load shared functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/git-session-lib.sh"

# Consume stdin (hooks receive JSON but we may not need session_id here)
cat >/dev/null 2>&1 || true

# Find the active session state file for this repo
STATE_FILE=$(claude_find_latest_state) || {
    echo "[claude-git] No active session state found, skipping checkpoint" >&2
    exit 0
}

# Read state
claude_read_state "$STATE_FILE" || {
    echo "[claude-git] Failed to read state file, skipping checkpoint" >&2
    exit 0
}

echo "[claude-git] Checkpoint on $SESSION_BRANCH" >&2

# Take snapshot
CHECKPOINT_NUM=$(claude_increment_checkpoint "$STATE_FILE")
if claude_snapshot "$SESSION_BRANCH" "WIP: checkpoint #${CHECKPOINT_NUM} before compaction $(date -Iseconds)"; then
    echo "[claude-git] Checkpoint #${CHECKPOINT_NUM} captured" >&2
else
    echo "[claude-git] No changes to checkpoint" >&2
fi

exit 0
