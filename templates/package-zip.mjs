#!/usr/bin/env node
import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const buildJsonPath = path.join(rootDir, 'build.json');

// 1. Get build number
let buildNumber = 'unknown';
try {
  const buildInfo = JSON.parse(fs.readFileSync(buildJsonPath, 'utf8'));
  buildNumber = buildInfo.number || 'unknown';
} catch (err) {
  console.warn('[MCM Packager] Warning: Could not read build.json, using "unknown"');
}

const zipName = `MCM-app-${buildNumber}.zip`;
const zipPath = path.join(rootDir, zipName);

console.log(`[MCM Packager] Packaging build #${buildNumber} into ${zipName}...`);

// 2. Clean up ALL old ZIPs matching the pattern
try {
  const files = fs.readdirSync(rootDir);
  const zipPattern = /^MCM-[Aa]pp-.*\.zip$/;
  let deletedCount = 0;
  for (const file of files) {
    if (zipPattern.test(file)) {
      const fullPath = path.join(rootDir, file);
      fs.unlinkSync(fullPath);
      deletedCount++;
    }
  }
  if (deletedCount > 0) {
    console.log(`[MCM Packager] Removed ${deletedCount} old build(s).`);
  }
} catch (err) {
  console.warn(`[MCM Packager] Warning: Could not clean up old builds: ${err.message}`);
}

// 3. Create ZIP using system command
try {
  if (process.platform === 'win32') {
    // Windows PowerShell
    const cmd = `PowerShell -Command "Compress-Archive -Path 'dist', 'local_server' -DestinationPath '${zipName}' -Force"`;
    execSync(cmd, { cwd: rootDir, stdio: 'inherit' });
  } else {
    // macOS/Linux zip
    // -r recursive, -q quiet
    const cmd = `zip -rq "${zipName}" dist local_server`;
    execSync(cmd, { cwd: rootDir, stdio: 'inherit' });
  }
  
  console.log(`[MCM Packager] Successfully created: ${zipName}`);
  console.log(`[MCM Packager] Size: ${Math.round(fs.statSync(zipPath).size / 1024)} KB`);
} catch (err) {
  console.error('[MCM Packager] Error creating ZIP:', err.message);
  process.exit(1);
}
