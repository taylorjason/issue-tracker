const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const pkgPath = path.join(__dirname, '../package.json');
const htmlPath = path.join(__dirname, '../index.html');

try {
  // 1. Update package.json
  const pkgData = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
  const version = pkgData.version || '1.0.0';
  const currentBuild = typeof pkgData.build === 'number' ? pkgData.build : 0;
  
  const newBuild = currentBuild + 1;
  pkgData.build = newBuild;
  
  fs.writeFileSync(pkgPath, JSON.stringify(pkgData, null, 2) + '\n');
  
  // 2. Update index.html
  const versionString = `v${version} (Build ${newBuild})`;
  let htmlData = fs.readFileSync(htmlPath, 'utf8');

  // Regex to look for a specific marker: <div id="app-version">...</div>
  const versionRegex = /(<div\s+id="app-version"[^>]*>)[^<]*(<\/div>)/i;
  const titleRegex = /(<title>)[^<]*(<\/title>)/i;
  const newTitle = `Issue Tracker v${version}(${newBuild})`;
  
  if (versionRegex.test(htmlData)) {
    htmlData = htmlData.replace(versionRegex, `$1\n        ${versionString}$2`);
    
    // Also update the title tag
    if (titleRegex.test(htmlData)) {
      htmlData = htmlData.replace(titleRegex, `$1${newTitle}$2`);
    } else {
      console.warn(`\x1b[33m⚠ Warning: Could not find <title></title> in index.html\x1b[0m`);
    }

    fs.writeFileSync(htmlPath, htmlData);
    console.log(`\x1b[32m✔ Bumped to ${versionString}\x1b[0m`);
    
    // Automatically stage the changes
    execSync('git add package.json index.html');
  } else {
    console.warn(`\x1b[33m⚠ Warning: Could not find <div id="app-version"></div> in index.html\x1b[0m`);
  }

} catch (err) {
  console.error('\x1b[31m✖ Failed to bump version:\x1b[0m', err.message);
  process.exit(1);
}
