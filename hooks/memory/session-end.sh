#!/bin/bash
# Stop Hook (Session End) - Persist learnings when session ends
#
# Runs when Claude session ends. Creates/updates session log file
# with timestamp for continuity tracking.
#
# Hook config (in ~/.claude/settings.json):
# {
#   "hooks": {
#     "Stop": [{
#       "matcher": "*",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/claude-code-hooks/memory/session-end.sh"
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
  # Fallback if no session_id provided
  SESSION_ID_SHORT="unknown"
fi

SESSIONS_DIR="${HOME}/.claude/sessions"
TODAY=$(date '+%Y-%m-%d')
SESSION_FILE="${SESSIONS_DIR}/${TODAY}-${SESSION_ID_SHORT}-session.md"

mkdir -p "$SESSIONS_DIR"

# If session file exists for today, update the end time
if [ -f "$SESSION_FILE" ]; then
  # Update Last Updated timestamp
  sed -i "s/\*\*Last Updated:\*\*.*/\*\*Last Updated:\*\* $(date '+%H:%M')/" "$SESSION_FILE" 2>/dev/null || \
  sed -i '' "s/\*\*Last Updated:\*\*.*/\*\*Last Updated:\*\* $(date '+%H:%M')/" "$SESSION_FILE" 2>/dev/null
  echo "[SessionEnd] Updated session file: $SESSION_FILE" >&2
else
  # Create new session file with template
  cat > "$SESSION_FILE" << EOF
# Session: $(date '+%Y-%m-%d')
**Date:** $TODAY
**Started:** $(date '+%H:%M')
**Last Updated:** $(date '+%H:%M')
**Session ID:** $SESSION_ID
**Session Dir:** \`~/.claude/session-env/$SESSION_ID/\`

---

## Current State

[Session context goes here]

### Completed
- [ ]

### In Progress
- [ ]

### Notes for Next Session
-

### Context to Load
\`\`\`
[relevant files]
\`\`\`
EOF
  echo "[SessionEnd] Created session file: $SESSION_FILE" >&2
fi
