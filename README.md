# claude-code-hooks

Productivity hooks for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that add **session memory**, **automatic plan file renaming**, and **git safety checks**.

## What Are Claude Code Hooks?

Claude Code supports [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) — custom scripts that run automatically at specific lifecycle events (session start, session end, before compaction, before tool use). Hooks let you extend Claude Code's behavior without modifying the tool itself.

## Hooks Included

### Session Memory (`hooks/memory/`)

Track session context across Claude Code sessions.

| Hook | Event | What It Does |
|------|-------|-------------|
| `session-start.sh` | SessionStart | Scans for recent session files and learned skills, reports availability to stderr |
| `session-end.sh` | Stop | Creates/updates a dated session log (`~/.claude/sessions/YYYY-MM-DD-XXXXXXXX-session.md`) with timestamps and tracking sections |
| `pre-compact.sh` | PreCompact | Logs compaction events and annotates the active session file before Claude summarizes context |

**Why?** Claude Code sessions are ephemeral. These hooks create a paper trail so you (and Claude) can pick up where you left off.

### Plan Auto-Rename (`hooks/plan-rename/`)

Automatically rename Claude's randomly-generated plan files to descriptive, dated names.

| Hook | Event | What It Does |
|------|-------|-------------|
| `rename-plan.js` | Stop + SessionStart | Detects random plan names (e.g., `bubbly-imagining-stearns.md`) and renames them based on content (e.g., `20260211-1620-add-user-auth.md`) |

Title extraction priority:
1. Frontmatter `title:` field
2. First `# H1` heading
3. First line of `## Overview` section (if >= 20 chars)
4. First meaningful line >= 20 chars

**Why?** Claude Code generates random three-word plan filenames that are impossible to find later. This hook makes plan files searchable and dated.

> **Note:** The rename hook runs on both Stop and SessionStart because the Stop hook can be unreliable when Claude is in plan mode. Running at SessionStart catches any plans missed during the previous session's shutdown.

### Git Safety (`hooks/cicd/`)

Pre-commit validation for SSH, GPG signing, and sensitive file detection.

| Hook | Event | What It Does |
|------|-------|-------------|
| `pre-commit-guard.sh` | PreToolUse | Validates SSH connectivity, GPG signing config, and scans for sensitive staged files before `git commit` |

Three validation stages:
1. **SSH connectivity** (BLOCKING) — tests `ssh -T git@github.com`; blocks commit on failure
2. **GPG signing** (warnings) — checks `commit.gpgsign`, `tag.gpgsign`, signing key configured
3. **Sensitive files** (warnings) — scans staged files for `.env`, private keys, credentials, API keys

**Why?** Prevents commits over HTTPS (when SSH should be used), unsigned commits, and accidental secret exposure.

## Quick Start

### Option A: Install Script

```bash
git clone https://github.com/HornetGit/claude-code-hooks.git
cd claude-code-hooks
bash install.sh
```

Then add the hook configuration to `~/.claude/settings.json` (the script prints the snippet).

### Option B: Manual Setup

1. Copy hooks to your preferred location:
```bash
mkdir -p ~/.claude/hooks/claude-code-hooks
cp -r hooks/* ~/.claude/hooks/claude-code-hooks/
```

2. Add to `~/.claude/settings.json` (merge with existing config):
```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-code-hooks/memory/session-end.sh"
          },
          {
            "type": "command",
            "command": "node ~/.claude/hooks/claude-code-hooks/plan-rename/rename-plan.js",
            "timeout": 10
          }
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-code-hooks/memory/session-start.sh"
          },
          {
            "type": "command",
            "command": "node ~/.claude/hooks/claude-code-hooks/plan-rename/rename-plan.js",
            "timeout": 10
          }
        ]
      }
    ],
    "PreCompact": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-code-hooks/memory/pre-compact.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash(git commit*)",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/claude-code-hooks/cicd/pre-commit-guard.sh"
          }
        ]
      }
    ]
  }
}
```

3. Make scripts executable:
```bash
chmod +x ~/.claude/hooks/claude-code-hooks/memory/*.sh
chmod +x ~/.claude/hooks/claude-code-hooks/cicd/*.sh
```

## Pick and Choose

You don't need all hooks. Install only what you want:

- **Session memory only** — copy `hooks/memory/`, wire `Stop`, `SessionStart`, and `PreCompact` events
- **Plan rename only** — copy `hooks/plan-rename/`, wire `Stop` and `SessionStart` events
- **Git safety only** — copy `hooks/cicd/`, wire `PreToolUse` event

## Configuration

### Plan Rename (`config.json`)

The plan rename hook works with sensible defaults. To customize, copy `config.example.json` to `config.json` in the `plan-rename/` directory:

```bash
cp hooks/plan-rename/config.example.json hooks/plan-rename/config.json
```

| Option | Default | Description |
|--------|---------|-------------|
| `enabled` | `true` | Enable/disable the hook |
| `timestamp_prefix` | `true` | Prepend `YYYYMMDD-HHMM-` to renamed files |
| `slug_max_length` | `50` | Maximum characters for the title slug |
| `fallback_behavior` | `"keep_original"` | When no title found: `"keep_original"` or `"use_date_only"` |
| `collision_strategy` | `"append_number"` | On name collision: `"append_number"` or `"add_timestamp"` |
| `exclude_patterns` | `["*-agent-*.md"]` | Glob patterns to skip |
| `notify_user` | `true` | Show rename messages in Claude output |
| `dry_run` | `false` | Log renames without actually renaming |

## Hook Events Reference

| Hook | Lifecycle Event | Receives stdin? | Blocking? |
|------|----------------|-----------------|-----------|
| `session-start.sh` | SessionStart | No | No |
| `session-end.sh` | Stop | Yes (JSON with `session_id`) | No |
| `pre-compact.sh` | PreCompact | Yes (JSON with `session_id`) | No |
| `rename-plan.js` | Stop + SessionStart | No | No |
| `pre-commit-guard.sh` | PreToolUse | No | Yes (exit 1 blocks commit on SSH failure) |

## Requirements

- **Claude Code** CLI installed
- **Node.js** (for plan-rename hook)
- **Bash** (for memory and cicd hooks)
- **SSH key** configured for GitHub (for pre-commit-guard)
- **GPG key** configured (optional — pre-commit-guard warns but doesn't block without it)

## Troubleshooting

**Hooks not firing:**
- Check `~/.claude/settings.json` has the correct `hooks` block
- Verify the `matcher` patterns match (use `"*"` to match all, or `"Bash(git commit*)"` for specific tools)
- Restart Claude Code after changing settings

**Permission denied:**
```bash
chmod +x ~/.claude/hooks/claude-code-hooks/memory/*.sh
chmod +x ~/.claude/hooks/claude-code-hooks/cicd/*.sh
```

**GPG_TTY not set:**
The pre-commit-guard hook sets `GPG_TTY` automatically if needed. If GPG signing still fails, add to your shell profile:
```bash
export GPG_TTY=$(tty)
```

**Plan files not being renamed:**
- Set `DEBUG=1` to enable debug logging: `DEBUG=1 node hooks/plan-rename/rename-plan.js`
- Check `/tmp/rename-plan-debug.log` for output
- The hook only renames files matching Claude's random three-word pattern (e.g., `adjective-verb-name.md`)

**Session files:**
Session logs are stored in `~/.claude/sessions/`. Compaction events are logged to `~/.claude/sessions/compaction-log.txt`.

## License

MIT
