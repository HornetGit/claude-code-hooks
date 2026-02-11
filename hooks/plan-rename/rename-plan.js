#!/usr/bin/env node
/**
 * SessionEnd Hook - Auto-rename plan files
 *
 * Renames plan files from random names (bubbly-imagining-stearns.md)
 * to descriptive names based on content (2024-01-25-plugin-setup.md)
 */

const path = require('path');
const fs = require('fs');
const {
  getClaudeDir,
  getDateString,
  readFile,
  log
} = require('./lib/utils');
const {
  loadConfig,
  extractTitle,
  generateNewName,
  isRandomName,
  shouldExclude,
  resolveCollision
} = require('./lib/plan-utils');

/**
 * Main execution
 */
async function main() {
  // Debug logging (set DEBUG=1 to enable)
  if (process.env.DEBUG) {
    const debugLogPath = '/tmp/rename-plan-debug.log';
    fs.appendFileSync(debugLogPath, `[${new Date().toISOString()}] Hook started\n`);
  }

  const config = loadConfig();

  if (!config.enabled) {
    log('[PlanRename] Disabled via config');
    process.exit(0);
  }

  const plansDir = path.join(getClaudeDir(), 'plans');
  if (!fs.existsSync(plansDir)) {
    process.exit(0);
  }

  // Find plan files with random names
  const files = fs.readdirSync(plansDir)
    .filter(f => f.endsWith('.md'))
    .filter(f => isRandomName(f))
    .filter(f => !shouldExclude(f, config.exclude_patterns));

  if (files.length === 0) {
    if (config.notify_user) {
      log('[PlanRename] No random-named plan files found');
    }
    process.exit(0);
  }

  for (const filename of files) {
    const sourcePath = path.join(plansDir, filename);
    let content;

    try {
      content = readFile(sourcePath);
    } catch (err) {
      log(`[PlanRename] Could not read: ${filename} - ${err.message}`);
      continue;
    }

    if (!content) {
      log(`[PlanRename] Empty file, skipping: ${filename}`);
      continue;
    }

    // Extract title
    const title = extractTitle(content, config);

    if (!title) {
      if (config.fallback_behavior === 'keep_original') {
        if (config.notify_user) {
          log(`[PlanRename] No title found, keeping: ${filename}`);
        }
        continue;
      } else if (config.fallback_behavior === 'use_date_only') {
        const newName = `${getDateString()}-plan.md`;
        let targetPath = path.join(plansDir, newName);
        targetPath = resolveCollision(targetPath, config.collision_strategy);

        if (!targetPath) {
          log(`[PlanRename] Name collision, skipping: ${filename}`);
          continue;
        }

        if (config.dry_run) {
          log(`[PlanRename] DRY RUN: ${filename} → ${path.basename(targetPath)}`);
        } else {
          try {
            fs.renameSync(sourcePath, targetPath);
            if (config.notify_user) {
              log(`[PlanRename] Renamed: ${filename} → ${path.basename(targetPath)}`);
            }
          } catch (err) {
            log(`[PlanRename] Error renaming ${filename}: ${err.message}`);
          }
        }
      }
      continue;
    }

    // Generate new name
    const newName = generateNewName(title, config, getDateString);
    let targetPath = path.join(plansDir, newName);

    // Handle collisions
    targetPath = resolveCollision(targetPath, config.collision_strategy);
    if (!targetPath) {
      log(`[PlanRename] Name collision, skipping: ${filename}`);
      continue;
    }

    // Perform rename (or dry run)
    if (config.dry_run) {
      log(`[PlanRename] DRY RUN: ${filename} → ${path.basename(targetPath)}`);
    } else {
      try {
        fs.renameSync(sourcePath, targetPath);
        if (config.notify_user) {
          log(`[PlanRename] Renamed: ${filename} → ${path.basename(targetPath)}`);
        }
      } catch (err) {
        log(`[PlanRename] Error renaming ${filename}: ${err.message}`);
      }
    }
  }

  process.exit(0);
}

main().catch(err => {
  log(`[PlanRename] Fatal error: ${err.message}`);
  process.exit(0);
});
