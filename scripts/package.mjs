import fs from 'fs';
import path from 'path';
import { execSync } from 'child_process';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

// 1. Get version and build number
let version = '0.0.0';
let build = '0';

try {
  const vJson = JSON.parse(fs.readFileSync(path.join(rootDir, 'version.json'), 'utf8'));
  version = vJson.version || '0.0.0';
  
  const pJson = JSON.parse(fs.readFileSync(path.join(rootDir, 'package.json'), 'utf8'));
  build = pJson.build || '0';
} catch (err) {
  console.warn('[Nova Packager] Warning: Could not read version/build info, using defaults.');
}

const zipName = `nova-${version}(${build}).zip`;
const zipPath = path.join(rootDir, zipName);

console.log(`[Nova Packager] Packaging Nova v${version} (Build #${build}) into ${zipName}...`);

// 2. Clean up ALL old ZIPs matching the pattern
try {
  const files = fs.readdirSync(rootDir);
  const zipPattern = /^nova-.*\.zip$/;
  let deletedCount = 0;
  for (const file of files) {
    if (zipPattern.test(file)) {
      const fullPath = path.join(rootDir, file);
      fs.unlinkSync(fullPath);
      deletedCount++;
    }
  }
  if (deletedCount > 0) {
    console.log(`[Nova Packager] Cleaned up ${deletedCount} old build(s).`);
  }
} catch (err) {
  console.warn(`[Nova Packager] Warning: Could not clean up old builds: ${err.message}`);
}

// 3. Create ZIP using system command
try {
  if (process.platform === 'win32') {
    // Windows PowerShell - Note: Compress-Archive is a bit limited for exclusions
    // We'll just zip the requested components. If users have data in scripts/data, it might be included.
    const cmd = `PowerShell -Command "Compress-Archive -Path 'index.html', 'scripts' -DestinationPath '${zipName}' -Force"`;
    execSync(cmd, { cwd: rootDir, stdio: 'inherit' });
  } else {
    // macOS/Linux zip
    // -r recursive, -q quiet, -x exclude local data
    const cmd = `zip -rq "${zipName}" index.html scripts -x "scripts/data/*"`;
    execSync(cmd, { cwd: rootDir, stdio: 'inherit' });
  }
  
  console.log(`[Nova Packager] Successfully created: ${zipName}`);
  console.log(`[Nova Packager] Size: ${Math.round(fs.statSync(zipPath).size / 1024)} KB`);
} catch (err) {
  console.error('[Nova Packager] Error creating ZIP:', err.message);
  process.exit(1);
}
