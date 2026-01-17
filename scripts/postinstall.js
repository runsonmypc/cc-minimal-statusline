#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const scriptPath = path.join(__dirname, '..', 'statusline.sh');
const configDir = path.join(os.homedir(), '.claude');
const settingsPath = path.join(configDir, 'settings.json');

console.log('\n📊 cc-minimal-statusline installed!\n');
console.log('To enable, add this to your ~/.claude/settings.json:\n');
console.log(`{
  "statusLine": {
    "type": "command",
    "command": "${scriptPath}",
    "padding": 0
  }
}`);
console.log('\n💡 Tip: Make sure you have a Nerd Font installed for icons to display correctly.');
console.log('   brew install --cask font-meslo-lg-nerd-font\n');
