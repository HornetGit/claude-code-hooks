#!/bin/bash
# PreCompact Hook - Save state before context compaction
#
# Runs before Claude compacts context, giving you a chance to
# preserve important state that might get lost in summarization.
#
# Hook config (in ~/.claude/settings.json):
# {
#   "hooks": {
#     "PreCompact": [{
#       "matcher": "*",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/claude-code-hooks/memory/pre-compact.sh"
#       }]
#     }]
#   }
# }

# Read session data from stdin (JSON format)
STDIN_DATA=$(cat)
SESSION_ID=$(echo "$STDIN_DATA" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)

# Extract first 8 chars of session ID for filename
if [ -n "$SESSION_ID" ]; then
  SESSION_ID_SHORT="${SESSION_ID:0:8}"
else
  SESSION_ID_SHORT=""
fi

SESSIONS_DIR="${HOME}/.claude/sessions"
COMPACTION_LOG="${SESSIONS_DIR}/compaction-log.txt"
TODAY=$(date '+%Y-%m-%d')

mkdir -p "$SESSIONS_DIR"

# Log compaction event with timestamp and session ID
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Context compaction triggered (session: $SESSION_ID_SHORT)" >> "$COMPACTION_LOG"

# If there's an active session file for this session, note the compaction
if [ -n "$SESSION_ID_SHORT" ]; then
  ACTIVE_SESSION="${SESSIONS_DIR}/${TODAY}-${SESSION_ID_SHORT}-session.md"
  if [ -f "$ACTIVE_SESSION" ]; then
    echo "" >> "$ACTIVE_SESSION"
    echo "---" >> "$ACTIVE_SESSION"
    echo "**[Compaction occurred at $(date '+%H:%M')]** - Context was summarized" >> "$ACTIVE_SESSION"
  fi
else
  # Fallback: find most recent session file
  ACTIVE_SESSION=$(ls -t "$SESSIONS_DIR"/*.md 2>/dev/null | head -1)
  if [ -n "$ACTIVE_SESSION" ]; then
    echo "" >> "$ACTIVE_SESSION"
    echo "---" >> "$ACTIVE_SESSION"
    echo "**[Compaction occurred at $(date '+%H:%M')]** - Context was summarized" >> "$ACTIVE_SESSION"
  fi
fi

echo "[PreCompact] State saved before compaction" >&2
