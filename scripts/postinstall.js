#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');

const configDir = path.join(os.homedir(), '.claude');
const settingsPath = path.join(configDir, 'settings.json');

const statusLineConfig = {
  type: 'command',
  command: 'cc-minimal-statusline',
  padding: 0
};

// Create .claude directory if it doesn't exist
if (!fs.existsSync(configDir)) {
  fs.mkdirSync(configDir, { recursive: true });
}

let settings = {};

// Read existing settings if they exist
if (fs.existsSync(settingsPath)) {
  try {
    const content = fs.readFileSync(settingsPath, 'utf8');
    settings = JSON.parse(content);
  } catch (e) {
    console.log('Warning: Could not parse existing settings.json, creating backup...');
    fs.copyFileSync(settingsPath, settingsPath + '.backup');
    settings = {};
  }
}

// Add statusLine config
settings.statusLine = statusLineConfig;

// Write settings
fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n');

console.log('\n📊 cc-minimal-statusline installed and configured!\n');
console.log('✅ Added to ~/.claude/settings.json\n');
console.log('💡 Tip: Make sure you have a Nerd Font installed for icons to display correctly.');
console.log('   brew install --cask font-meslo-lg-nerd-font\n');
