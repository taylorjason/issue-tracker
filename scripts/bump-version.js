const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const pkgPath = path.join(__dirname, '../package.json');
const verPath = path.join(__dirname, '../version.json');
const htmlPath = path.join(__dirname, '../index.html');

try {
  // 1. Read sources
  const pkgData = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
  const verData = JSON.parse(fs.readFileSync(verPath, 'utf8'));
  
  // 2. Determine base version from version.json
  const currentVersion = verData.version || '1.1.0';
  const parts = currentVersion.split('.').map(Number);
  
  // Increment patch version
  if (parts.length === 3) {
    parts[2]++;
  } else {
    parts.push(1);
  }
  const newVersion = parts.join('.');
  
  // 3. Increment build number (from package.json)
  const currentBuild = typeof pkgData.build === 'number' ? pkgData.build : 0;
  const newBuild = currentBuild + 1;
  
  // 4. Update data objects
  pkgData.version = newVersion;
  pkgData.build = newBuild;
  verData.version = newVersion;
  
  // 5. Write JSONs
  fs.writeFileSync(pkgPath, JSON.stringify(pkgData, null, 2) + '\n');
  fs.writeFileSync(verPath, JSON.stringify(verData, null, 2) + '\n');
  
  // 6. Update index.html
  let htmlData = fs.readFileSync(htmlPath, 'utf8');
  
  // App version div string
  const versionString = `v${newVersion} (Build ${newBuild})`;
  // Window title string
  const newTitle = `Issue Tracker v${newVersion}(${newBuild})`;
  
  // Regex to look for markers
  const versionRegex = /(<div\s+id="app-version"[^>]*>)[^<]*(<\/div>)/i;
  const titleRegex = /(<title>)[^<]*(<\/title>)/i;
  
  let updated = false;
  if (versionRegex.test(htmlData)) {
    htmlData = htmlData.replace(versionRegex, `$1${versionString}$2`);
    updated = true;
  }
  if (titleRegex.test(htmlData)) {
    htmlData = htmlData.replace(titleRegex, `$1${newTitle}$2`);
    updated = true;
  }
  
  if (updated) {
    fs.writeFileSync(htmlPath, htmlData);
    console.log(`\x1b[32m✔ Bumped to ${versionString}\x1b[0m`);
    
    // Automatically stage the changes
    try {
      execSync('git add package.json version.json index.html');
      console.log(`\x1b[32m✔ Staged changes in Git\x1b[0m`);
    } catch (e) {
      // Silently fail if git is not available
    }
  } else {
    console.warn(`\x1b[33m⚠ Warning: Could not find version markers in index.html\x1b[0m`);
  }

} catch (err) {
  console.error('\x1b[31m✖ Failed to bump version:\x1b[0m', err.message);
  process.exit(1);
}
