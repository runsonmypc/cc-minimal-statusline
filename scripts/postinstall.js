#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');
const readline = require('readline');

const configDir = path.join(os.homedir(), '.claude');
const settingsPath = path.join(configDir, 'settings.json');

const statusLineConfig = {
  type: 'command',
  command: 'cc-minimal-statusline',
  padding: 0
};

function configureSettings() {
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
  console.log('\n✅ Status line configured in ~/.claude/settings.json');
  console.log('\n💡 Tip: Make sure you have a Nerd Font installed for icons to display correctly.');
  console.log('   brew install --cask font-meslo-lg-nerd-font\n');
}

function showManualInstructions() {
  console.log('\nTo enable manually, add this to your ~/.claude/settings.json:\n');
  console.log(JSON.stringify({ statusLine: statusLineConfig }, null, 2));
  console.log('\n💡 Tip: Make sure you have a Nerd Font installed for icons to display correctly.');
  console.log('   brew install --cask font-meslo-lg-nerd-font\n');
}

// Check if running in interactive terminal
if (!process.stdin.isTTY) {
  console.log('\n📊 cc-minimal-statusline installed!');
  showManualInstructions();
  process.exit(0);
}

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

console.log('\n📊 cc-minimal-statusline installed!\n');

rl.question('Configure Claude Code to use this status line? (Y/n) ', (answer) => {
  rl.close();

  const shouldConfigure = !answer || answer.toLowerCase() === 'y' || answer.toLowerCase() === 'yes';

  if (shouldConfigure) {
    configureSettings();
  } else {
    showManualInstructions();
  }
});
