#!/bin/bash
# SessionStart Hook - Auto-sync Claude Code plugin source to cache
#
# Detects plugin source directories and syncs changed files to the
# corresponding frozen cache. Runs on SessionStart so that edits made
# between sessions are picked up automatically.
#
# Discovery:
#   Scans PLUGIN_ROOTS (default: ~/.claude/) for directories containing
#   a .claude-plugin/plugin.json. For each, derives the cache path from
#   the plugin name/version and syncs source → cache when changes are
#   detected (using a .last-sync marker file).
#
# Override scan roots via environment:
#   PLUGIN_ROOTS="/path/one:/path/two" (colon-separated)
#
# Requires: bash, rsync, jq (optional — falls back to grep)

set -Eeuo pipefail
IFS=$'\n\t'

CACHE_BASE="${HOME}/.claude/plugins/cache"
PLUGIN_ROOTS="${PLUGIN_ROOTS:-${HOME}/.claude}"
SYNCED=0
SKIPPED=0

# Parse plugin.json for name and version
# Uses jq if available, otherwise grep fallback
parse_json_field() {
  local file="$1" field="$2"
  if command -v jq &>/dev/null; then
    jq -r ".${field} // empty" "$file" 2>/dev/null
  else
    grep -o "\"${field}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
      | head -1 | sed 's/.*":\s*"\(.*\)"/\1/'
  fi
}

# Scan each root for plugin source directories
IFS=':' read -ra ROOTS <<< "$PLUGIN_ROOTS"
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue

  # Find all plugin.json manifests (max depth 5 to avoid deep traversal)
  while IFS= read -r manifest; do
    SOURCE_DIR="$(dirname "$(dirname "$manifest")")"
    PLUGIN_NAME="$(parse_json_field "$manifest" "name")"
    PLUGIN_VERSION="$(parse_json_field "$manifest" "version")"

    # Skip if missing required fields
    if [ -z "$PLUGIN_NAME" ] || [ -z "$PLUGIN_VERSION" ]; then
      continue
    fi

    # Derive cache path: cache/<org>/<name>/<version>/
    # Convention: org = directory name containing plugin source
    PLUGIN_ORG="$(basename "$(dirname "$SOURCE_DIR")")"
    CACHE_DIR="${CACHE_BASE}/${PLUGIN_ORG}/${PLUGIN_NAME}/${PLUGIN_VERSION}"
    SYNC_MARKER="${CACHE_DIR}/.last-sync"

    # Skip if source IS the cache (avoid self-sync)
    REAL_SOURCE="$(realpath "$SOURCE_DIR" 2>/dev/null || echo "$SOURCE_DIR")"
    REAL_CACHE="$(realpath "$CACHE_DIR" 2>/dev/null || echo "$CACHE_DIR")"
    if [ "$REAL_SOURCE" = "$REAL_CACHE" ]; then
      continue
    fi

    # Case 1: Cache doesn't exist — full sync
    if [ ! -d "$CACHE_DIR" ]; then
      mkdir -p "$CACHE_DIR"
      rsync -a --delete "${SOURCE_DIR}/" "$CACHE_DIR/"
      touch "$SYNC_MARKER"
      echo "[plugin-cache-sync] Created cache: ${PLUGIN_ORG}/${PLUGIN_NAME}/${PLUGIN_VERSION}" >&2
      SYNCED=$((SYNCED + 1))
      continue
    fi

    # Case 2: No marker — force sync
    if [ ! -f "$SYNC_MARKER" ]; then
      rsync -a --delete "${SOURCE_DIR}/" "$CACHE_DIR/"
      touch "$SYNC_MARKER"
      echo "[plugin-cache-sync] Synced (no marker): ${PLUGIN_ORG}/${PLUGIN_NAME}/${PLUGIN_VERSION}" >&2
      SYNCED=$((SYNCED + 1))
      continue
    fi

    # Case 3: Check for changes since last sync
    CHANGED=$(find "$SOURCE_DIR" -newer "$SYNC_MARKER" -type f 2>/dev/null | head -1)
    if [ -n "$CHANGED" ]; then
      rsync -a --delete "${SOURCE_DIR}/" "$CACHE_DIR/"
      touch "$SYNC_MARKER"
      echo "[plugin-cache-sync] Synced (changes detected): ${PLUGIN_ORG}/${PLUGIN_NAME}/${PLUGIN_VERSION}" >&2
      SYNCED=$((SYNCED + 1))
    else
      SKIPPED=$((SKIPPED + 1))
    fi

  done < <(find "$root" -maxdepth 5 -path "*/.claude-plugin/plugin.json" -type f 2>/dev/null)
done

if [ "$SYNCED" -eq 0 ] && [ "$SKIPPED" -eq 0 ]; then
  echo "[plugin-cache-sync] No plugin sources found" >&2
elif [ "$SYNCED" -gt 0 ]; then
  echo "[plugin-cache-sync] ${SYNCED} plugin(s) synced, ${SKIPPED} up to date" >&2
else
  echo "[plugin-cache-sync] ${SKIPPED} plugin(s) up to date" >&2
fi

exit 0
