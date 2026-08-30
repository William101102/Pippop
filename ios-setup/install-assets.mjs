#!/usr/bin/env node
/**
 * Copies the generated icon and splash into the Xcode asset catalogs.
 *
 * Rather than hardcoding Apple's filenames, which have changed between Xcode
 * versions, this overwrites whichever PNGs the Capacitor template already put
 * in each catalog. That keeps it working when the template is regenerated.
 *
 * Usage: node ios-setup/install-assets.mjs
 */
import { copyFileSync, existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

const CATALOG = 'ios/App/App/Assets.xcassets';
const ICON = 'ios-setup/assets/AppIcon-1024.png';
const SPLASH = 'ios-setup/assets/splash-2732.png';

if (!existsSync(CATALOG)) {
  console.error(`${CATALOG} not found. Run "npm run ios:add" first.`);
  process.exit(1);
}
for (const asset of [ICON, SPLASH]) {
  if (!existsSync(asset)) {
    console.error(`${asset} not found. Run "python3 ios-setup/generate-icons.py" first.`);
    process.exit(1);
  }
}

function fill(setName, source) {
  const dir = join(CATALOG, setName);
  if (!existsSync(dir)) {
    console.log(`  skipped ${setName} (not in this template)`);
    return;
  }
  const targets = readdirSync(dir).filter((name) => name.toLowerCase().endsWith('.png'));
  if (targets.length === 0) {
    console.log(`  skipped ${setName} (no PNG slots)`);
    return;
  }
  for (const target of targets) copyFileSync(source, join(dir, target));
  console.log(`  ${setName}: ${targets.join(', ')}`);
}

console.log('Installing app assets into the Xcode catalog');
fill('AppIcon.appiconset', ICON);
fill('Splash.imageset', SPLASH);
