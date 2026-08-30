#!/usr/bin/env node
/**
 * Adds Pinpop's iOS permission strings and background mode to the generated
 * Xcode project. `npx cap add ios` writes a stock Info.plist and regenerating
 * the platform overwrites it, so this is re-runnable and idempotent.
 *
 * Usage: node ios-setup/apply-info-plist.mjs
 */
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

const PLIST = 'ios/App/App/Info.plist';

const ENTRIES = [
  [
    'NSLocationWhenInUseUsageDescription',
    '<string>Pinpop 用你的位置把你显示在地图上，只有你已通过的好友能看到，你可以随时切换为模糊或冻结。</string>',
  ],
  [
    'NSLocationAlwaysAndWhenInUseUsageDescription',
    '<string>允许「始终」后，即使 Pinpop 在后台，好友也能看到你最新的位置。关闭后好友只会看到你最后一次打开应用时的位置。</string>',
  ],
  [
    'NSLocationAlwaysUsageDescription',
    '<string>允许「始终」后，即使 Pinpop 在后台，好友也能看到你最新的位置。</string>',
  ],
  ['NSPhotoLibraryUsageDescription', '<string>选择一张照片作为你的 Pinpop 头像。</string>'],
  ['NSCameraUsageDescription', '<string>拍一张照片作为你的 Pinpop 头像。</string>'],
  ['UIBackgroundModes', '<array>\n\t\t<string>location</string>\n\t</array>'],
  ['UIViewControllerBasedStatusBarAppearance', '<false/>'],
];

if (!existsSync(PLIST)) {
  console.error(`${PLIST} not found. Run "npx cap add ios" first.`);
  process.exit(1);
}

let plist = readFileSync(PLIST, 'utf8');
const added = [];
const skipped = [];

for (const [key, value] of ENTRIES) {
  if (plist.includes(`<key>${key}</key>`)) {
    skipped.push(key);
    continue;
  }
  // Insert before the final closing </dict> of the root dictionary.
  const anchor = plist.lastIndexOf('</dict>');
  if (anchor === -1) {
    console.error('Malformed plist: no closing </dict>.');
    process.exit(1);
  }
  plist = `${plist.slice(0, anchor)}\t<key>${key}</key>\n\t${value}\n${plist.slice(anchor)}`;
  added.push(key);
}

writeFileSync(PLIST, plist);
console.log(`${PLIST}`);
if (added.length) console.log(`  added:   ${added.join(', ')}`);
if (skipped.length) console.log(`  present: ${skipped.join(', ')}`);
