#!/bin/bash
# install.sh - Install claude-code-hooks to ~/.claude/hooks/claude-code-hooks/
#
# Usage: bash install.sh [DEST]
#   DEST  Install location (default: ~/.claude/hooks/claude-code-hooks)
#
# Does NOT modify settings.json. Prints the snippet you need to add manually.

set -euo pipefail

DEST="${1:-${HOME}/.claude/hooks/claude-code-hooks}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "[install] Installing claude-code-hooks to ${DEST}/"
echo ""

# Create directories
mkdir -p "${DEST}/memory"
mkdir -p "${DEST}/plan-rename/lib"
mkdir -p "${DEST}/cicd"
mkdir -p "${DEST}/plugin-sync"

# Copy hooks (cp -af preserves permissions, overwrites in place)
cp -af "${SCRIPT_DIR}/hooks/memory/session-start.sh"      "${DEST}/memory/"
cp -af "${SCRIPT_DIR}/hooks/memory/session-end.sh"         "${DEST}/memory/"
cp -af "${SCRIPT_DIR}/hooks/memory/pre-compact.sh"         "${DEST}/memory/"
cp -af "${SCRIPT_DIR}/hooks/plan-rename/rename-plan.js"    "${DEST}/plan-rename/"
cp -af "${SCRIPT_DIR}/hooks/plan-rename/lib/plan-utils.js" "${DEST}/plan-rename/lib/"
cp -af "${SCRIPT_DIR}/hooks/plan-rename/lib/utils.js"      "${DEST}/plan-rename/lib/"
cp -af "${SCRIPT_DIR}/hooks/cicd/pre-commit-guard.sh"      "${DEST}/cicd/"
cp -af "${SCRIPT_DIR}/hooks/plugin-sync/plugin-cache-sync.sh" "${DEST}/plugin-sync/"

# Copy config example if no config.json exists yet
if [ ! -f "${DEST}/plan-rename/config.json" ]; then
  cp -af "${SCRIPT_DIR}/hooks/plan-rename/config.example.json" "${DEST}/plan-rename/config.example.json"
fi

# Make bash scripts executable
chmod +x "${DEST}/memory/"*.sh
chmod +x "${DEST}/cicd/"*.sh
chmod +x "${DEST}/plugin-sync/"*.sh

echo "[install] Done! Hooks installed to: ${DEST}"
echo ""
echo "Next step: Add hook configuration to ~/.claude/settings.json"
echo "See examples/settings.json for the complete snippet, or the README for details."
echo ""
echo "Installed hooks:"
echo "  ${DEST}/memory/session-start.sh    (SessionStart)"
echo "  ${DEST}/memory/session-end.sh      (Stop)"
echo "  ${DEST}/memory/pre-compact.sh      (PreCompact)"
echo "  ${DEST}/plan-rename/rename-plan.js  (Stop + SessionStart)"
echo "  ${DEST}/cicd/pre-commit-guard.sh   (PreToolUse)"
echo "  ${DEST}/plugin-sync/plugin-cache-sync.sh (SessionStart)"
