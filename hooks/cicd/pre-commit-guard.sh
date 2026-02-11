#!/bin/bash
# PreToolUse Hook - SSH + GPG + .gitignore guard before git commit
#
# Runs before git commit to validate:
# 1. SSH connectivity to GitHub
# 2. GPG agent running and signing configured
# 3. No sensitive files staged
#
# Hook config (in ~/.claude/settings.json):
# {
#   "hooks": {
#     "PreToolUse": [{
#       "matcher": "Bash(git commit*)",
#       "hooks": [{
#         "type": "command",
#         "command": "~/.claude/hooks/claude-code-hooks/cicd/pre-commit-guard.sh"
#       }]
#     }]
#   }
# }

set -Eeuo pipefail
IFS=$'\n\t'

ERRORS=0
WARNINGS=0

# --- 1. SSH Connectivity ---
# ssh -T always exits 1 (GitHub doesn't provide shell access), so capture output first
SSH_OUTPUT=$(ssh -T git@github.com 2>&1 || true)
if ! echo "$SSH_OUTPUT" | grep -qi "successfully authenticated"; then
  echo "[pre-commit-guard] SSH authentication to GitHub failed. Fix SSH keys before committing." >&2
  echo "[pre-commit-guard] Output: $SSH_OUTPUT" >&2
  ERRORS=$((ERRORS + 1))
fi

# --- 2. GPG Signing ---
# Ensure GPG_TTY is set
if [ -z "${GPG_TTY:-}" ]; then
  GPG_TTY=$(tty 2>/dev/null || echo "")
  if [ -n "$GPG_TTY" ]; then
    echo "[pre-commit-guard] Set GPG_TTY=$GPG_TTY" >&2
  fi
fi

# Launch gpg-agent if not running
if ! gpgconf --launch gpg-agent 2>/dev/null; then
  echo "[pre-commit-guard] WARNING: Could not launch gpg-agent. Signed commits may fail." >&2
  WARNINGS=$((WARNINGS + 1))
fi

# Check commit.gpgsign
COMMIT_SIGN=$(git config --global --get commit.gpgsign 2>/dev/null || echo "")
if [ "$COMMIT_SIGN" != "true" ]; then
  echo "[pre-commit-guard] WARNING: commit.gpgsign is not true. Run: git config --global commit.gpgsign true" >&2
  WARNINGS=$((WARNINGS + 1))
fi

# Check tag.gpgsign
TAG_SIGN=$(git config --global --get tag.gpgsign 2>/dev/null || echo "")
if [ "$TAG_SIGN" != "true" ]; then
  echo "[pre-commit-guard] WARNING: tag.gpgsign is not true. Run: git config --global tag.gpgsign true" >&2
  WARNINGS=$((WARNINGS + 1))
fi

# Check signing key exists
SIGNING_KEY=$(git config --global --get user.signingkey 2>/dev/null || echo "")
if [ -z "$SIGNING_KEY" ]; then
  echo "[pre-commit-guard] WARNING: No signing key configured. Run: git config --global user.signingkey <KEY_ID>" >&2
  WARNINGS=$((WARNINGS + 1))
fi

# --- 3. Sensitive Files Check ---
STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || echo "")

if [ -n "$STAGED_FILES" ]; then
  # Patterns that should never be committed
  SENSITIVE_PATTERNS='\.env$|\.env\.|credentials|\.key$|\.pem$|\.p12$|\.pfx$|id_rsa|id_dsa|id_ed25519|id_ecdsa|\.secret|api_key|apikey|password|\.git-credentials|service-account.*\.json'

  SENSITIVE_MATCHES=$(echo "$STAGED_FILES" | grep -iE "$SENSITIVE_PATTERNS" || echo "")

  if [ -n "$SENSITIVE_MATCHES" ]; then
    echo "[pre-commit-guard] WARNING: Potentially sensitive files staged for commit:" >&2
    echo "$SENSITIVE_MATCHES" | while read -r file; do
      echo "  - $file" >&2
    done
    echo "[pre-commit-guard] Consider adding these to .gitignore before committing." >&2
    WARNINGS=$((WARNINGS + 1))
  fi
fi

# --- Summary ---
if [ "$ERRORS" -gt 0 ]; then
  echo "[pre-commit-guard] BLOCKED: $ERRORS error(s), $WARNINGS warning(s). Fix errors before committing." >&2
  exit 1
fi

if [ "$WARNINGS" -gt 0 ]; then
  echo "[pre-commit-guard] PASSED with $WARNINGS warning(s). Review above." >&2
fi

exit 0
