/**
 * Plan Utilities - Shared logic for plan file renaming
 * Used by both the SessionEnd hook and the save-plan command
 */

const path = require('path');
const fs = require('fs');

/**
 * Load configuration from config.json (optional, falls back to defaults)
 * Looks for config.json in the same directory as rename-plan.js
 */
function loadConfig() {
  const defaultConfig = {
    enabled: true,
    timestamp_prefix: true,
    date_format: 'YYYYMMDD-HHMM',
    slug_max_length: 50,
    fallback_behavior: 'keep_original',
    collision_strategy: 'append_number',
    extraction_sources: [
      'frontmatter_title',
      'first_h1',
      'overview_section',
      'first_meaningful_line'
    ],
    exclude_patterns: ['*-agent-*.md'],
    notify_user: true,
    dry_run: false
  };

  try {
    const configPath = path.join(__dirname, '..', 'config.json');

    if (fs.existsSync(configPath)) {
      const configContent = fs.readFileSync(configPath, 'utf8');
      const userConfig = JSON.parse(configContent);
      return { ...defaultConfig, ...userConfig };
    }
  } catch (err) {
    // Config load failed, use defaults
  }

  return defaultConfig;
}

/**
 * Extract title from plan content using priority strategy
 */
function extractTitle(content, config) {
  if (!content) return null;

  // 1. Try frontmatter title
  const frontmatterMatch = content.match(/^---\n([\s\S]+?)\n---/);
  if (frontmatterMatch) {
    const titleMatch = frontmatterMatch[1].match(/^title:\s*(.+)$/m);
    if (titleMatch) {
      const title = titleMatch[1].trim().replace(/^["']|["']$/g, '');
      if (title.length > 0) return title;
    }
  }

  // 2. Try first H1
  const h1Match = content.match(/^#\s+(.+)$/m);
  if (h1Match) {
    const title = h1Match[1].trim();
    if (title.length > 0) return title;
  }

  // 3. Try Overview section
  const overviewMatch = content.match(/##\s+Overview\s*\n+(.+)/);
  if (overviewMatch) {
    const firstLine = overviewMatch[1].split('\n')[0].trim();
    if (firstLine.length >= 20) return firstLine;
  }

  // 4. Fallback to first meaningful line
  const lines = content.split('\n')
    .map(l => l.trim())
    .filter(l => l.length >= 20 && !l.startsWith('#') && !l.startsWith('-'));

  if (lines.length > 0) {
    return lines[0].substring(0, 100);
  }

  return null;
}

/**
 * Convert title to filesystem-safe slug
 */
function titleToSlug(title, maxLength) {
  return title
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, '')
    .replace(/\s+/g, '-')
    .replace(/-+/g, '-')
    .substring(0, maxLength)
    .replace(/^-+|-+$/g, '');
}

/**
 * Generate new filename from title
 */
function generateNewName(title, config, getDateString) {
  const slug = titleToSlug(title, config.slug_max_length);

  if (config.timestamp_prefix) {
    const date = getDateString();
    return `${date}-${slug}.md`;
  }

  return `${slug}.md`;
}

/**
 * Check if filename matches random pattern
 * Claude Code generates names like: bubbly-imagining-stearns.md
 * Pattern: exactly 3 words, each 4-15 chars, all lowercase, no numbers or underscores
 */
function isRandomName(filename) {
  // First check: matches basic pattern
  if (!/^[a-z]+-[a-z]+-[a-z]+(-agent-[a-z0-9]+)?\.md$/i.test(filename)) {
    return false;
  }

  // Additional checks to avoid false positives:
  // - Random names don't contain underscores
  if (filename.includes('_')) {
    return false;
  }

  // - Random names don't start with dates (YYYYMMDD-HHMM)
  if (/^\d{8}-\d{4}/.test(filename)) {
    return false;
  }

  // - Each word should be 3-15 characters (typical for adjectives/names)
  const parts = filename.replace('.md', '').replace(/-agent-[a-z0-9]+$/, '').split('-');
  if (parts.length !== 3) {
    return false;
  }

  // Check word lengths are typical for random names (not too long)
  return parts.every(part => part.length >= 3 && part.length <= 15);
}

/**
 * Check if filename matches exclude patterns
 */
function shouldExclude(filename, patterns) {
  return patterns.some(pattern => {
    const regex = new RegExp('^' + pattern.replace(/\*/g, '.*') + '$');
    return regex.test(filename);
  });
}

/**
 * Handle name collisions by appending number or timestamp
 */
function resolveCollision(targetPath, strategy) {
  if (!fs.existsSync(targetPath)) return targetPath;

  const dir = path.dirname(targetPath);
  const ext = path.extname(targetPath);
  const base = path.basename(targetPath, ext);

  if (strategy === 'append_number') {
    let counter = 2;
    while (fs.existsSync(path.join(dir, `${base}-${counter}${ext}`))) {
      counter++;
      if (counter > 100) return null; // Safety limit
    }
    return path.join(dir, `${base}-${counter}${ext}`);
  }

  if (strategy === 'add_timestamp') {
    const timestamp = new Date().toTimeString().split(' ')[0].replace(/:/g, '');
    const newPath = path.join(dir, `${base}-${timestamp}${ext}`);
    if (!fs.existsSync(newPath)) return newPath;
  }

  // skip
  return null;
}

module.exports = {
  loadConfig,
  extractTitle,
  titleToSlug,
  generateNewName,
  isRandomName,
  shouldExclude,
  resolveCollision
};
